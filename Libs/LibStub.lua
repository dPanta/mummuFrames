-- Minimal LibStub implementation (compatible with embedded Ace-style libs)
local LIBSTUB_MAJOR, LIBSTUB_MINOR = "LibStub", 2
local LibStub = _G[LIBSTUB_MAJOR]

if not LibStub or (LibStub.minor or 0) < LIBSTUB_MINOR then
    LibStub = LibStub or {
        libs = {},
        minors = {},
    }
    _G[LIBSTUB_MAJOR] = LibStub
    LibStub.minor = LIBSTUB_MINOR

    function LibStub:NewLibrary(major, minor)
        if type(major) ~= "string" then
            error("Bad argument #1 to NewLibrary (string expected)", 2)
        end
        minor = tonumber(minor)
        if not minor then
            error("Bad argument #2 to NewLibrary (number expected)", 2)
        end

        local oldMinor = self.minors[major]
        if oldMinor and oldMinor >= minor then
            return nil
        end

        self.minors[major] = minor
        self.libs[major] = self.libs[major] or {}
        return self.libs[major], oldMinor
    end

    function LibStub:GetLibrary(major, silent)
        local lib = self.libs[major]
        if not lib and not silent then
            error(("Cannot find a library instance of %q."):format(tostring(major)), 2)
        end
        return lib, self.minors[major]
    end

    function LibStub:IterateLibraries()
        return pairs(self.libs)
    end

    setmetatable(LibStub, {
        __call = function(self, ...)
            return self:GetLibrary(...)
        end,
    })
end
