/*
    SDL - Simple DirectMedia Layer
    Copyright (C) 1997-2012 Sam Lantinga
    Copyright (C) 2015-2016 Phillip Camp
    Copyright (C) 2014-2015 Manuel Alfayate Corchete

    This library is free software; you can redistribute it and/or
    modify it under the terms of the GNU Lesser General Public
    License as published by the Free Software Foundation; either
    version 2.1 of the License, or (at your option) any later version.

    This library is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
    Lesser General Public License for more details.

    You should have received a copy of the GNU Lesser General Public
    License along with this library; if not, write to the Free Software
    Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA

    Sam Lantinga
    slouken@libsdl.org

	Dispmanx driver by Manuel Alfayate Corchete
	redwindwanderer@gmail.com

    Dispmanx FB accel intergration Phillip Camp
*/
#include "SDL_config.h"



#include <stdio.h>
#include <string.h>

#include "SDL_video.h"
#include "SDL_fbvideo.h"
#include "SDL_fbevents_c.h"
#include "../SDL_pixels_c.h"

#define DEBUG_DISPMANX

#ifdef SDL_VIDEO_DRIVER_FBCON_ACCEL_DISPMANX
#include <bcm_host.h>
#include <stdbool.h>

#include <fcntl.h>
#include <linux/fb.h>
#include <sys/mman.h>
#include <sys/ioctl.h>

#define min(a,b)      ((a)<(b)?(a):(b))
#define RGB565(r,g,b) (((r)>>3)<<11 | ((g)>>2)<<5 | (b)>>3)

/* Initialization/Query functions */
static SDL_Rect **DISPMANX_ListModes(_THIS, SDL_PixelFormat *format, Uint32 flags);
static SDL_Surface *DISPMANX_SetVideoMode(_THIS, SDL_Surface *current, int width, int height, int bpp, Uint32 flags);
static int DISPMANX_SetColors(_THIS, int firstcolor, int ncolors, SDL_Color *colors);
static void DISPMANX_VideoQuit(_THIS);

/* Hardware surface functions */
static int DISPMANX_WaitVBL(_THIS);
static int DISPMANX_WaitIdle(_THIS);
static void DISPMANX_DirectUpdate(_THIS, int numrects, SDL_Rect *rects);
static void DISPMANX_BlankBackground(void);
static void DISPMANX_FreeResources(void);
static void DISPMANX_FreeBackground(void);

typedef struct {
	DISPMANX_DISPLAY_HANDLE_T   display;
	DISPMANX_DISPLAY_HANDLE_T   display_alt;
	DISPMANX_MODEINFO_T         amode;
	DISPMANX_MODEINFO_T         amode_alt;
	void                        *pixmem;
	DISPMANX_UPDATE_HANDLE_T    update;
	DISPMANX_RESOURCE_HANDLE_T  resources[2];
	DISPMANX_ELEMENT_HANDLE_T   element;
	DISPMANX_ELEMENT_HANDLE_T   element_alt;
	VC_IMAGE_TYPE_T             pix_format;
	uint32_t                    vc_image_ptr;
	VC_DISPMANX_ALPHA_T         *alpha;
	VC_RECT_T                   src_rect;
	VC_RECT_T                   dst_rect;
	VC_RECT_T                   dst_rect_alt;
	VC_RECT_T                   fbcp_rect;
	VC_RECT_T                   bmp_rect;
	int bits_per_pixel;
	int pitch;

	DISPMANX_RESOURCE_HANDLE_T  b_resource;
	DISPMANX_ELEMENT_HANDLE_T   b_element;
	DISPMANX_ELEMENT_HANDLE_T   b_element_alt;
	DISPMANX_UPDATE_HANDLE_T    b_update;

	int ignore_ratio;

	// fbcp
	DISPMANX_RESOURCE_HANDLE_T  fbcp_resource;
	int fbfd;
	char *fbcp;
	char *fbp;
	int fbcp_pitch;
	size_t smem_len;
} __DISPMAN_VARIABLES_T;


static __DISPMAN_VARIABLES_T _DISPMAN_VARS;
static __DISPMAN_VARIABLES_T *dispvars = &_DISPMAN_VARS;

void fbcp(DISPMANX_UPDATE_HANDLE_T u, void* arg) {
	vc_dispmanx_snapshot(dispvars->display, dispvars->fbcp_resource, 0);
	vc_dispmanx_resource_read_data(dispvars->fbcp_resource, &(dispvars->fbcp_rect), dispvars->fbp, dispvars->fbcp_pitch);
}

static SDL_Surface *DISPMANX_SetVideoMode(_THIS, SDL_Surface *current, int width, int height, int bpp, Uint32 flags)
{
	// Allow thse to change on a mode setting.
	dispvars->ignore_ratio = (int) SDL_getenv("SDL_DISPMANX_IGNORE_RATIO");
	dispvars->fbcp = SDL_getenv("SDL_DISPMANX_FBCP");

	if ((width == 0) | (height == 0)) goto go_video_console;

	if ( ! dispvars->display ) {
		char *no = SDL_getenv("SDL_DISPMANX_DISPLAY");
		int display_no = no ?  atoi(no) : 0;
		bcm_host_init();

		dispvars->display = vc_dispmanx_display_open(display_no);
		vc_dispmanx_display_get_info( dispvars->display, &(dispvars->amode));
#ifdef DEBUG_DISPMANX
		printf( "Dispmanx: Physical video mode is %d x %d for display %d\n", dispvars->amode.width, dispvars->amode.height,display_no );
#endif

		no = SDL_getenv("SDL_DISPMANX_DISPLAY_ALT");
		display_no = no ?  atoi(no) : 0; 
		if (no && ! dispvars->display_alt ) {
			dispvars->display_alt = vc_dispmanx_display_open(display_no);
			vc_dispmanx_display_get_info( dispvars->display_alt, &(dispvars->amode_alt));
#ifdef DEBUG_DISPMANX
			printf( "Dispmanx: Alt Physical video mode is %d x %d for display %d\n", dispvars->amode_alt.width, dispvars->amode_alt.height,display_no );
#endif
		}

		if (dispvars->fbcp && ! dispvars->fbfd) {
			dispvars->fbfd = open(dispvars->fbcp, O_RDWR);
			if (dispvars->fbfd) {
				struct fb_var_screeninfo vinfo;
				struct fb_fix_screeninfo finfo;

				ioctl(dispvars->fbfd, FBIOGET_FSCREENINFO, &finfo);
				ioctl(dispvars->fbfd, FBIOGET_VSCREENINFO, &vinfo);
				dispvars->fbcp_pitch = vinfo.xres * vinfo.bits_per_pixel / 8;
#ifdef DEBUG_DISPMANX
				fprintf(stderr, "fbcp display %s is %d x %d %dbps\n", dispvars->fbcp , vinfo.xres, vinfo.yres, vinfo.bits_per_pixel);
#endif
				dispvars->fbcp_resource = vc_dispmanx_resource_create(VC_IMAGE_RGB565, vinfo.xres, vinfo.yres,  &(dispvars->vc_image_ptr));
				dispvars->fbp = (char*) mmap(0, finfo.smem_len, PROT_READ | PROT_WRITE, MAP_SHARED, dispvars->fbfd, 0);
				dispvars->smem_len = finfo.smem_len;
				vc_dispmanx_rect_set(&(dispvars->fbcp_rect), 0, 0, vinfo.xres, vinfo.yres);
			}
		}
		DISPMANX_BlankBackground();
	} else {
		free(dispvars->pixmem);
		DISPMANX_FreeResources();
	}
	Uint32 Rmask;
	Uint32 Gmask;
	Uint32 Bmask;

	dispvars->bits_per_pixel = bpp;
	dispvars->pitch = ( ALIGN_UP( width, 16 ) * (bpp/8) );

	height = ALIGN_UP( height, 16);

	switch (bpp) {
		case 8:
			dispvars->pix_format = VC_IMAGE_8BPP;
			break;
		case 16:
			dispvars->pix_format = VC_IMAGE_RGB565;
			break;
		case 32:
			dispvars->pix_format = VC_IMAGE_XRGB8888;
			break;
		default:
			// FIXME std ERROR
			fprintf (stderr,"Dispmanx: [ERROR] - wrong bpp: %d\n",bpp);
			return (NULL);
	}

#ifdef DEBUG_DISPMANX
	printf ("Dispmanx: Using internal program mode: %d x %d %d bpp\n",
		width, height, dispvars->bits_per_pixel);

	printf ("Dispmanx: Using physical mode: %d x %d %d bpp\n",
		dispvars->amode.width, dispvars->amode.height,
		dispvars->bits_per_pixel);
#endif

	if (dispvars->ignore_ratio)
		vc_dispmanx_rect_set( &(dispvars->dst_rect), 0, 0, dispvars->amode.width , dispvars->amode.height );
	else {
		float width_scale, height_scale;
		width_scale = (float) dispvars->amode.width / width;
		height_scale = (float) dispvars->amode.height / height;
		float scale = min(width_scale, height_scale);
		int dst_width = width * scale;
		int dst_height = height * scale;
		int dst_xpos  = (dispvars->amode.width - dst_width) / 2;
		int dst_ypos  = (dispvars->amode.height - dst_height) / 2;
#ifdef DEBUG_DISPMANX
		printf ("Dispmanx: Scaling to %d x %d\n", dst_width, dst_height);
#endif
		vc_dispmanx_rect_set( &(dispvars->dst_rect), dst_xpos, dst_ypos,
		dst_width , dst_height );

		if (dispvars->display_alt) {
		float width_scale, height_scale;
		width_scale = (float) dispvars->amode_alt.width / width;
		height_scale = (float) dispvars->amode_alt.height / height;
		float scale = min(width_scale, height_scale);
		int dst_width = width * scale;
		int dst_height = height * scale;
		int dst_xpos  = (dispvars->amode_alt.width - dst_width) / 2;
		int dst_ypos  = (dispvars->amode_alt.height - dst_height) / 2;
#ifdef DEBUG_DISPMANX
		printf ("Dispmanx: Alt Scaling to %d x %d\n", dst_width, dst_height);
#endif
		vc_dispmanx_rect_set( &(dispvars->dst_rect_alt), dst_xpos, dst_ypos,
		dst_width , dst_height );
		}
	}

	vc_dispmanx_rect_set (&(dispvars->bmp_rect), 0, 0, width, height);

	vc_dispmanx_rect_set (&(dispvars->src_rect), 0, 0, width << 16, height << 16);

	VC_DISPMANX_ALPHA_T layerAlpha;

	layerAlpha.flags = DISPMANX_FLAGS_ALPHA_FIXED_ALL_PIXELS;
	layerAlpha.opacity = 255;
	layerAlpha.mask	   = 0;
	dispvars->alpha = &layerAlpha;

	// dispvars->vc_image_ptr is historic and set to 0
	dispvars->resources[0] = vc_dispmanx_resource_create( dispvars->pix_format, width, height, &(dispvars->vc_image_ptr) );
	dispvars->resources[1] = vc_dispmanx_resource_create( dispvars->pix_format, width, height, &(dispvars->vc_image_ptr) );

	dispvars->pixmem = calloc( 1, dispvars->pitch * height);

	Rmask = 0;
	Gmask = 0;
	Bmask = 0;
	if ( ! SDL_ReallocFormat(current, bpp, Rmask, Gmask, Bmask, 0) ) {
		return(NULL);
	}

	current->w = width;
	current->h = height;

	current->pitch  = dispvars->pitch;
	current->pixels = dispvars->pixmem;
	//current->flags |= SDL_DOUBLEBUF;

	dispvars->update = vc_dispmanx_update_start( 0 );

	/* setup display */
	dispvars->element = vc_dispmanx_element_add( dispvars->update,
		dispvars->display, 0 /*layer*/, &(dispvars->dst_rect),
		dispvars->resources[flip_page], &(dispvars->src_rect),
		DISPMANX_PROTECTION_NONE, dispvars->alpha, 0 /*clamp*/,
		/*VC_IMAGE_ROT0*/ 0 );
	if (dispvars->display_alt) {
		dispvars->element_alt = vc_dispmanx_element_add( dispvars->update,
			dispvars->display_alt, 0 /*layer*/, &(dispvars->dst_rect_alt),
			dispvars->resources[flip_page], &(dispvars->src_rect),
			DISPMANX_PROTECTION_NONE, dispvars->alpha, 0 /*clamp*/,
			/*VC_IMAGE_ROT0*/ 0 );
	}	

	vc_dispmanx_update_submit_sync( dispvars->update );
	this->UpdateRects = DISPMANX_DirectUpdate;

	go_video_console:
	if ( FB_EnterGraphicsMode(this) < 0 )
		return(NULL);

	return(current);
}

static void DISPMANX_BlankBackground(void)
{
	VC_IMAGE_TYPE_T type = VC_IMAGE_RGB565;
	uint32_t vc_image_ptr;
	uint16_t image = 0x0000; // black

	VC_RECT_T dst_rect, src_rect;

	dispvars->b_resource = vc_dispmanx_resource_create( type, 1 /*width*/, 1 /*height*/, &vc_image_ptr );

	vc_dispmanx_rect_set( &dst_rect, 0, 0, 1, 1);

	vc_dispmanx_resource_write_data( dispvars->b_resource, type, sizeof(image), &image, &dst_rect );

	vc_dispmanx_rect_set( &src_rect, 0, 0, 1<<16, 1<<16);
	vc_dispmanx_rect_set( &dst_rect, 0, 0, 0, 0);

	dispvars->b_update = vc_dispmanx_update_start(0);

	dispvars->b_element = vc_dispmanx_element_add(dispvars->b_update, dispvars->display, -1 /*layer*/, &dst_rect,
		dispvars->b_resource, &src_rect, DISPMANX_PROTECTION_NONE, NULL, NULL, (DISPMANX_TRANSFORM_T)0 );

	if (dispvars->display_alt) {
		dispvars->b_element = vc_dispmanx_element_add(dispvars->b_update, dispvars->display_alt, -1 /*layer*/, &dst_rect,
		dispvars->b_resource, &src_rect, DISPMANX_PROTECTION_NONE, NULL, NULL, (DISPMANX_TRANSFORM_T)0 );
	}
	vc_dispmanx_update_submit_sync( dispvars->b_update );
	// FIXME - Invesigate we may be leeking these
	// Free backgound at each mode change before calling this?
}

static int DISPMANX_WaitVBL(_THIS)
{
#ifdef DEBUG_DISPMANX
	fprintf (stderr,"Dispmanx: WaitVBL\n");
	dispvars->update = vc_dispmanx_update_start( 0 );
	vc_dispmanx_update_submit_sync( dispvars->update );
#endif
	return 0;
}

static int DISPMANX_WaitIdle(_THIS)
{
	// called on VT switch need to hide displamx elements
#ifdef DEBUG_DISPMANX
	fprintf (stderr,"Dispmanx: WaitIDLE\n");
#endif
	dispvars->update = vc_dispmanx_update_start( 0 );
	vc_dispmanx_element_remove(dispvars->update, dispvars->element);
	vc_dispmanx_update_submit_sync( dispvars->update );

	DISPMANX_FreeBackground();
	vc_dispmanx_display_close( dispvars->display );
	dispvars->display = 0;

	return 0;
}

// copy the while surface here really?
static void DISPMANX_DirectUpdate(_THIS, int numrects, SDL_Rect *rects)
{
	if ( switched_away ) {
		return; /* no hardware access */
	}

	vc_dispmanx_resource_write_data( dispvars->resources[flip_page],
		dispvars->pix_format, dispvars->pitch, dispvars->pixmem,
		&(dispvars->bmp_rect) );

	dispvars->update = vc_dispmanx_update_start( 0 );
	if (!dispvars->display) {
#ifdef DEBUG_DISPMANX
		fprintf (stderr,"Dispmanx: restore form WaitIdle\n");
#endif
		char *no = SDL_getenv("SDL_DISPMANX_DISPLAY");
		int display_no = no ?  atoi(no) : 0;

		dispvars->display = vc_dispmanx_display_open(display_no);//FIXME Display no
		dispvars->element = vc_dispmanx_element_add( dispvars->update,
	        dispvars->display, 0 /*layer*/, &(dispvars->dst_rect),
	        dispvars->resources[flip_page], &(dispvars->src_rect),
	        DISPMANX_PROTECTION_NONE, dispvars->alpha, 0 /*clamp*/,
	        /*VC_IMAGE_ROT0*/ 0 );
	}

#ifdef DEBUG_DISPMANX
	//printf ("Dispmanx: DirectUpdate %d %d,%d %dx%d\n", numrects, rects[0].x, rects[0].y, rects[0].w, rects[0].h);
#endif
	vc_dispmanx_element_change_source(dispvars->update, dispvars->element, dispvars->resources[flip_page]);

	if (dispvars->display_alt) {
		vc_dispmanx_element_change_source(dispvars->update, dispvars->element_alt, dispvars->resources[flip_page]);
	}
	vc_dispmanx_update_submit( dispvars->update, NULL, dispvars ); // NULL is call back

	//dispvars->fbcp = SDL_getenv("SDL_DISPMANX_FBCP");
	if (dispvars->fbcp && dispvars->fbfd) {
		vc_dispmanx_snapshot(dispvars->display, dispvars->fbcp_resource, 0);
		vc_dispmanx_resource_read_data(dispvars->fbcp_resource, &(dispvars->fbcp_rect), dispvars->fbp, dispvars->fbcp_pitch);
	}
	flip_page = !flip_page;

	return;
}

static int DISPMANX_SetColors(_THIS, int firstcolor, int ncolors, SDL_Color *colors)
{
	int i;
	static unsigned short pal[256];
#ifdef DEBUG_DISPMANX
	fprintf (stderr,"Dispmanx: Colors\n");
#endif

	//Set up the colormap
	for (i = 0; i < ncolors; i++) {
		pal[i] = RGB565 ((colors[i]).r, (colors[i]).g, (colors[i]).b);
	}
	vc_dispmanx_resource_set_palette(  dispvars->resources[flip_page], pal, 0, sizeof pal );
	vc_dispmanx_resource_set_palette(  dispvars->resources[!flip_page], pal, 0, sizeof pal );

	return(1);
}

static SDL_Rect **DISPMANX_ListModes(_THIS, SDL_PixelFormat *format, Uint32 flags)
{
#ifdef DEBUG_DISPMANX
	fprintf (stderr,"Dispmanx: DISPMANX_ListModes\n");
#endif
	dispvars->fbcp = SDL_getenv("SDL_DISPMANX_FBCP");
	return((SDL_Rect **)-1);
}

static void DISPMANX_FreeResources(void){
	dispvars->update = vc_dispmanx_update_start( 0 );
	vc_dispmanx_element_remove(dispvars->update, dispvars->element);
	if(dispvars->display_alt) {
		vc_dispmanx_element_remove(dispvars->update, dispvars->element_alt);
	}
	vc_dispmanx_update_submit_sync( dispvars->update );

	vc_dispmanx_resource_delete( dispvars->resources[0] );
	vc_dispmanx_resource_delete( dispvars->resources[1] );
}

static void DISPMANX_FreeBackground (void) {
	dispvars->b_update = vc_dispmanx_update_start( 0 );

	vc_dispmanx_resource_delete( dispvars->b_resource );
	vc_dispmanx_element_remove ( dispvars->b_update, dispvars->b_element);
	if(dispvars->display_alt) {
		vc_dispmanx_element_remove ( dispvars->b_update, dispvars->b_element_alt);
	}

	vc_dispmanx_update_submit_sync( dispvars->b_update );
}

static void (*VideoQuit)(_THIS);
static void DISPMANX_VideoQuit(_THIS)
{
	if (dispvars->fbfd) {
		vc_dispmanx_vsync_callback(dispvars->display, NULL, NULL); // disable callback
		munmap(dispvars->fbp, dispvars->smem_len);
		close(dispvars->fbfd);
		vc_dispmanx_resource_delete(dispvars->fbcp_resource);
	} 

	if (dispvars->display) {
		DISPMANX_FreeBackground();
		DISPMANX_FreeResources();
		vc_dispmanx_display_close( dispvars->display );
		if (dispvars->display_alt) {
			vc_dispmanx_display_close( dispvars->display_alt );
			dispvars->display_alt = 0;
		}
		dispvars->display = 0;
	}
	VideoQuit(this);
}

void FB_DispmanxAccel(_THIS, __u32 card) {
	/* Save */
	VideoQuit = this->VideoQuit;
	/* We have hardware accelerated surface functions */
	wait_vbl = DISPMANX_WaitVBL;
	wait_idle = DISPMANX_WaitIdle;
	/* Set the function pointers */
//	this->VideoInit = DISPMANX_VideoInit;
	this->ListModes = DISPMANX_ListModes;
	this->SetVideoMode = DISPMANX_SetVideoMode;
	this->SetColors = DISPMANX_SetColors;
	this->AllocHWSurface = NULL;
	this->CheckHWBlit = NULL;
	this->FillHWRect = NULL;
	this->SetHWColorKey = NULL;
	this->SetHWAlpha = NULL;
	this->LockHWSurface = NULL;
	this->UnlockHWSurface = NULL;
	this->FreeHWSurface = NULL;
	this->FlipHWSurface = NULL;
	this->SetCaption = NULL;
	this->SetIcon = NULL;
	this->IconifyWindow = NULL;
	this->GrabInput = NULL;
	this->GetWMInfo = NULL;
	this->VideoQuit = DISPMANX_VideoQuit;
}
#endif
