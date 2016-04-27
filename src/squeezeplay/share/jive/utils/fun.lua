-- 
local type, pairs, setmetatable = type, pairs, setmetatable

module(...)

-- defines a new item that inherits from an existing item
function uses(parent, value, shallow)
        if parent == nil then
                log:warn("nil parent in _uses at:\n", debug.traceback())
        end
        local item = {}
        setmetatable(item, { __index = parent })
        for k,v in pairs(value or {}) do
                if not shallow and type(v) == 'table' and type(parent[k]) == 'table' then
                        -- recursively inherrit from parent item
                        item[k] = uses(parent[k], v)
                else   
                        item[k] = v
                end
        end

        return item
end

function map(f, t)
        local t2 = {}
        for k,v in pairs(t) do t2[k] = f(v) end
        return t2
end
