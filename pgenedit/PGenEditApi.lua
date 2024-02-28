local api = require("pgeneditDebugApi")
local format = string.format

-- remaining to do:
-- 1. add support for enums
-- 2. add support for const methods
-- 3. add support for overloaded methods
-- 4. currently only userdata represents C++ objects. Since they are garbage-collected by Lua, it's possible to have objects with invalid state in C++ after some debug calls and gc execution. Need to add a way to create a "weak" object, which will not be garbage-collected by Lua, but will be destroyed only when object is destroyed from C++ side, and will be just as functional as a regular object (except for __gc metamethod, which will not be called).
-- Obviously need to use tables to represent such objects, since they too support metatables, and aren't garbage collected.
-- Such objects will be used, if user wants to keep a reference to an object, which is owned by C++ (global variable for example).
-- TODO: notify lua about object destruction from C++ side?
-- 5. BIG ONE: implement struct operators as metamethods if appropriate (for example, __add for operator+), and also implement __eq for all classes (for operator==)
-- 6. support for C++ containers as class/struct members (std::vector, std::map, etc.). To be determined - is it better to return a special "reference" to container on __index, which would automatically modify the container every time it is changed, or return plain table and allow only __newindex to modify the container?
-- 7. implement caching for subobjects (as fields or inside containers), so that they are not recreated every time they are accessed
-- 8. for easy integration of member types (for example inner structs) and data members, store in metadata declaring type?


-- for functions need to handle:
-- 1. type checking for arguments and return types (including small value types range compatibility), C++ will also check this, but it's better to check it here too
-- 2. objects as arguments and return values
-- 3. error handling
-- 4. pass the number of arguments to C++ (for functions with default arguments or for checking if parameters are missing/extra)
-- 5. don't use type names to do the conversions if possible, use type ids instead

-- CONVENTION: for callables, those that reside at static address are only "methods", those that are reassignable fields (such at function pointers or std::function) are considered "methods" and "fields" at the same time

-- minor style convention I adopted: functions in metatables should be qualified with __, for consistency with built-in metamethods, and also to disambiguate them from regular functions

-- a version of assert that allows for specifying stack error level
function assertl(val, msg, level)
	if val == nil then
		error(msg, (level or 1) + 1)
	end
	return val
end

pgenedit = pgenedit or {}
tget(pgenedit, "debug").attemptTypeConversion = false -- if true, will attempt to convert parameters to correct type, if false, will throw an error

local cpp = tget(pgenedit, "cpp")
_G.cpp = cpp

local makeClass
local isObjectOfClassOrDerived
do
	local class = {}
	cpp.class = class
	-- pgenedit.cpp.class
	-- pgenedit.cpp.global
	local classContainerMT = {}
	local customIndexes = {
		["?isObjectOfClassOrDerived"] = isObjectOfClassOrDerived,
	}
	function classContainerMT.__index(t, key) -- if __index fires, this means that class is not yet created
		if customIndexes[key] then
			return customIndexes[key]
		end
		local cls = makeClass(key)
		rawset(t, key, cls)
		return cls
	end
	function classContainerMT.__newindex(t, key, value)
		error(format("Attempt to set class %q", key), 2)
	end
	setmetatable(class, classContainerMT)
end
-- pgenedit.class.wxWindow.new("test", nil, 0, 0, 0, 0)

-- userdata are objects created by lua, tables are objects created by C++ (so no automatic garbage collection happens)
local function isClassObject(obj)
	return obj and (type(obj) == "userdata" or type(obj) == "table") and getmetatable(obj) and getmetatable(obj).className
end
-- assign to global variable, so that it can be used in C++ code
pgenedit.cpp.isClassObject = isClassObject

local function isClass(entity)
	return entity and getmetatable(entity) and getmetatable(entity).className and getmetatable(entity).objectMetatable
end
pgenedit.cpp.isClass = isClass

function isObjectOfClassOrDerived(obj, checkName)
	if not isClassObject(obj) then
		return false
	end
	local objMT = getmetatable(obj)
	-- support both class name and class table
	if checkName == nil then
		checkName = getmetatable(obj).className
	else
		checkName = type(checkName) == "table" and getmetatable(checkName).name or checkName
	end
	if objMT.className == checkName then -- same class
		return true
	elseif table.find(objMT.classMetatable.bases, checkName) then -- first-level base class
		return true
	elseif cpp.class[checkName] then -- check recursively for all base classes
		for i, name in ipairs(cpp.class[checkName]["?bases"]) do
			if isObjectOfClassOrDerived(obj, name) then
				return true
			end
		end
	end
	return false
end

local integerTypeRanges = 
{
	["char"] = {min = -128, max = 127},
	["unsigned char"] = {min = 0, max = 255},
	["short"] = {min = -32768, max = 32767},
	["unsigned short"] = {min = 0, max = 65535},
	["int"] = {min = -2147483648, max = 2147483647},
	["unsigned int"] = {min = 0, max = 4294967295},
	["long"] = {min = -2147483648, max = 2147483647},
	["unsigned long"] = {min = 0, max = 4294967295},
	["long long"] = {min = -9223372036854775808, max = 9223372036854775807},
	["unsigned long long"] = {min = 0, max = 18446744073709551615},
}
--error(format(sCantConvertToNumber, funcNameForMessage, paramIndex, value), 3)
local sIntOutOfRange = "'%s': Parameter #%d is out of range for type %q (value is %d)"
local genericParamFormatStr = "'%s': Parameter #%d (%q) of type %q and value %q can't be converted to C++ type %q"
local sNotAnObject = "'%s': Argument #%d (%q) is not an object [userdata]"
local function validateOrConvertParameter(value, cppType, paramIndex, funcNameForMessage, noError)
	local expectedParamData = cppType
	-- gets type table, not parameter one (which contains parameter name and type subtable)
	local expectedCppTypeStr = expectedParamData.name
	if expectedParamData.isPointer then
		expectedCppTypeStr = expectedCppTypeStr .. "*"
	elseif expectedParamData.isReference then
		expectedCppTypeStr = expectedCppTypeStr .. "&"
	elseif expectedParamData.isConst then
		expectedCppTypeStr = "const " .. expectedCppTypeStr
	end
	local conv = pgenedit.debug.attemptTypeConversion
	local cppTypeName = cppType.name
	if integerTypeRanges[cppTypeName] then
		if type(value) == "number" then
			if value < integerTypeRanges[cppTypeName].min or value > integerTypeRanges[cppTypeName].max then
				error(format(sIntOutOfRange, funcNameForMessage, paramIndex, cppTypeName, value), 3)
			end
			return value
		elseif conv then
			if type(value) == "boolean" then
				return value and 1 or 0
			elseif value == nil then
				return 0
			elseif type(value) == "string" then
				local num = tonumber(value)
				if num then
					if num < integerTypeRanges[cppTypeName].min or num > integerTypeRanges[cppTypeName].max then
						error(format(sIntOutOfRange, funcNameForMessage, paramIndex, cppTypeName, num), 3)
					end
					return num
				end
			end
		end
		--local genericParamFormatStr = "'%s': Parameter #%d (%q) of type %q and value %q can't be converted to C++ type %q"
		error(format(genericParamFormatStr, funcNameForMessage, paramIndex, expectedParamData.name, type(value), value, expectedCppTypeStr), 3)
	elseif cppTypeName == "float" or cppTypeName == "double" or cppTypeName == "long double" then
		if type(value) == "number" then
			return value
		elseif conv then
			if type(value) == "boolean" then
				return value and 1 or 0
			elseif value == nil then
				return 0
			elseif type(value) == "string" then
				local num = tonumber(value)
				if num then
					return num
				end
			end
		end
		error(format(genericParamFormatStr, funcNameForMessage, paramIndex, expectedParamData.name, type(value), value, expectedCppTypeStr), 3)
	elseif cppTypeName == "bool" then
		if type(value) == "boolean" then
			return value
		-- TODO: consider if always doing nil -> false conversion, regardless of conv, is a good idea
		elseif conv then
			if type(value) == "number" then
				return value ~= 0
			elseif value == nil then
				return false
			elseif type(value) == "string" then
				if value == "true" then
					return true
				elseif value == "false" then
					return false
				end
			end
		end
		error(format(genericParamFormatStr, funcNameForMessage, paramIndex, expectedParamData.name, type(value), value, expectedCppTypeStr), 3)
	elseif table.find({"std::string", "std::string_view"}, cppTypeName) then -- for std::string, const char* and std::string_view
		-- not adding const char* right now, because it's hard to get exact type name right (spaces and all), maybe use field properties to detect it instead?
		if type(value) == "string" then
			return value
		elseif conv then
			if value == nil then
				return ""
			elseif type(value) == "boolean" then
				return value and "true" or "false"
			elseif type(value) == "number" then
				return tostring(value)
			end
		end
		error(format(genericParamFormatStr, funcNameForMessage, paramIndex, expectedParamData.name, type(value), value, expectedCppTypeStr), 3)
	elseif cppTypeName == "LuaTable" or expectedParamData.isSequentialContainer or expectedParamData.isAssociativeContainer then
		if type(value) == "table" then
			return value
		elseif conv then
			if value == nil then
				return {}
			end
		end
		error(format(genericParamFormatStr, funcNameForMessage, paramIndex, expectedParamData.name, type(value), value, expectedCppTypeStr), 3)
	elseif cppTypeName == "nil" then -- shouldn't ever happen
		error(format("'%s': Parameter #%d (%q) of type %q and value %q: requested C++ type is 'nil'", funcNameForMessage, paramIndex, expectedParamData.name, type(value), value), 3)
	elseif expectedParamData.isClass and not (expectedParamData.isSequentialContainer or expectedParamData.isAssociativeContainer) then
		if type(value) ~= "userdata" or not getmetatable(value) or not getmetatable(value).className then
			error(format(sNotAnObject, funcNameForMessage, paramIndex, value), 3)
		elseif getmetatable(cppTypeName).className ~= getmetatable(value).className and not isObjectOfClassOrDerived(value, cppTypeName) then
			error(format("'%s': Parameter %d (%q) is of invalid class (expected %q or any derived, got %q)", funcNameForMessage, paramIndex, expectedParamData.name, cppTypeName, getmetatable(value).className), 3)
		else
			return value
		end
	elseif noError then
		return
	else
		error(format("'%s': Parameter #%d (%q) of type %q and value %q: requested C++ type is %q, which is not supported", funcNameForMessage, paramIndex, expectedParamData.name, type(value), value, expectedCppTypeStr), 3)
	end
end

local function getDefParamCount(params)
	local defCount = 0
	for i = #params, 1, -1 do
		if params[i].hasDefaultValue then
			defCount = defCount + 1
		else
			break
		end
	end
	return defCount
end

-- if className is nil, then it's treated as a global/static function
local function funcWrapper(className, memberName, memberData)
	local fullFuncName = className and format("%s::%s", className, memberName) or memberName
	local params = memberData.params
	assert(memberData.isCallable, format("'%s': Member %q is not callable", fullFuncName, memberData.name))

	local isMemberMethod = className and memberData.isMethod
	local argCount, defCount = #params + (isMemberMethod and 1 or 0), getDefParamCount(params)
	assert(argCount >= defCount, format("'%s': Argument count (%d) is less than default argument count (%d)", fullFuncName, argCount, defCount))
	--assert(#params == argCount, format("'%s': Argument type count (%d) is not equal to argument count (%d)", fullFuncName, #params, argCount))
	-- RTTR get_parameter_infos() doesn't include object to invoke method on, so we need to add it manually
	return function(...)
		local args = {...}
		if #args < argCount - defCount then
			error(format("'%s': Not enough arguments (expected at least %d, got %d)", fullFuncName, argCount - defCount, #args), 2)
		elseif #args > argCount then
			error(format("'%s': Too many arguments (expected at most %d, got %d)", fullFuncName, argCount, #args), 2)
		end
		if not memberData.isConstructor then
			for i = 1, #params do -- check explicitly provided parameters
				-- args contains object pointer, params doesn't...
				local argIndex = i + (isMemberMethod and 1 or 0)
				local typ = params[i].type
				args[argIndex] = validateOrConvertParameter(args[argIndex], typ, i, fullFuncName)
			end
			-- if member is static or a field (std::function for example), then we don't need to process it
			if isMemberMethod then
				local this = args[1]
				if not api.classExists(className) then
					error(format("Class %q does not exist", className), 2)
				elseif type(this) ~= "userdata" and type(this) ~= "table" then
					error(format("Invalid object instance (first parameter), received %q", this), 2)
				elseif not getmetatable(this) then
					error(format("Object instance is not a valid object (no metatable)", this), 2)
				elseif getmetatable(this).className ~= className then
					error(format("Object instance is of invalid class (expected %q, got %q)", this, className, getmetatable(this).className), 2)
				end
			end
		end
		-- convert objects to pointers if possible
		-- COMMENTED OUT, because C++ needs to know the exact type of passed object
		-- for i, arg in pairs(args) do
		-- 	args[i] = type(arg) == "table" and arg["?ptr"] or arg
		-- end
		if not className then -- global
			return api.invokeGlobalMethod(memberName, #args, unpack(args))
		elseif memberData.isStatic then -- static class method
			return api.invokeClassMethod(className, memberName, #args, unpack(args))
		else
			return api.invokeClassObjectMethod(className, args[1], memberName, #args - 1, unpack(args, 2)) -- skips first argument, which is object pointer
		end
	end
end

-- entity can be class, class object, or global (nil)
local function getElementByPath(entity, fieldName, accessPath)
	local accessPath = table.copy(accessPath)
	table.insert(accessPath, 1, fieldName)
	local first = 1
	if entity == nil then -- global
		entity = cpp.global[accessPath[1]]
	elseif isClass(entity) then -- class
		-- do nothing
	else -- instance of class
		-- do nothing
	end
	for i = first, #accessPath do
		local val = entity[accessPath[i]]
		if val == nil then
			error(format("'%s': Attempt to access unknown field %q", getmetatable(entity).className, accessPath[i]), 4)
		end
		entity = val
	end
	return entity
end

local function getEntityMetadataByPath(entity, fieldName, accessPath)
	local first = 1
	local metadata
	if entity == nil then -- global
		metadata = cpp.global["?getMemberData"](fieldName)
	elseif isClass(entity) then -- class
		metadata = entity["?getMemberData"](fieldName)
	else -- instance of class
		metadata = entity["?getMetadata"](fieldName)
	end
	for i = first, #accessPath do
		local newMetadata
		if metadata.isAssociativeContainer then
			newMetadata = metadata.valueType -- always choose value type
		elseif metadata.isSequentialContainer or metadata.isWrapper then
			newMetadata = metadata.valueType
		else
			error(format("'%s': Attempt to access field %q of non-container type %q", getmetatable(entity).className, accessPath[i], metadata.name), 4)
		end
		metadata = newMetadata
	end
	return metadata
end

-- returns key, value, type metadata
local function enumMembersGeneric(members, obj, returnValues)
	return function(t, k)
		k = next(members, k)
		if k then
			if returnValues then
				return k, obj[k], members[k]
			else
				return k, members[k]
			end
		end
	end
end

-- need to know: whether field being assigned to is a container, if so, container type and its data type
-- TODO: handle LuaTable cpp class
local function assignTableToField(classObject, fieldName, accessPath, val)
	local obj = getElementByPath(classObject, fieldName, accessPath)
	local nestedMetadata = getEntityMetadataByPath(classObject, fieldName, accessPath)
	if nestedMetadata.isSequentialContainer then -- assign table to container
		-- TODO: sets (they are considered 'sequential container' in RTTR, but can have non-integer or sparse keys, so they are not really sequential)
		-- need to check that:
		-- there are no gaps in indexes
		-- data type is correct
		-- there are no non-integer keys
		local maxIndex = 0
		for k, v in pairs(val) do
			if type(k) ~= "number" then -- index type is not integer
				error(format("'%s': Attempt to assign table to sequential container %q with non-numeric key %q", getmetatable(classObject).className, fieldName, k), 3)
			elseif validateOrConvertParameter(v, nestedMetadata.valueType, 1, getmetatable(classObject).className, true) == nil then -- value type is not correct
				error(format("'%s': Attempt to assign table to sequential container %q with invalid value %q", getmetatable(classObject).className, fieldName, v), 3)
			else
				maxIndex = math.max(maxIndex, k)
			end
		end
		for i = 1, maxIndex do
			if val[i] == nil then -- gap in indexes
				error(format("'%s': Attempt to assign table to sequential container %q with gaps in indexes", getmetatable(classObject).className, fieldName), 3)
			end
		end
		-- TODO: this will be slow, because it will call __newindex for each element, make additional API functions?
		obj:clear()
		for i = 1, maxIndex do
			obj[i] = val[i]
		end
	elseif nestedMetadata.isAssociativeContainer then
		-- need to check that:
		-- key and value types are correct (for all keys and values)

		local debugOld = pgenedit.debug.attemptTypeConversion
		pgenedit.debug.attemptTypeConversion = false -- for consistency with assignment loop below
		for k, v in pairs(val) do
			if validateOrConvertParameter(k, nestedMetadata.keyType, 1, getmetatable(classObject).className, true) == nil then -- key type is not correct
				error(format("'%s': Attempt to assign table to associative container %q with invalid key %q", getmetatable(classObject).className, fieldName, k), 3)
			elseif validateOrConvertParameter(v, nestedMetadata.valueType, 1, getmetatable(classObject).className, true) == nil then -- value type is not correct
				error(format("'%s': Attempt to assign table to associative container %q with invalid value %q", getmetatable(classObject).className, fieldName, v), 3)
			end
		end
		obj:clear()
		for k, v in pairs(val) do
			obj[k] = v
		end
		pgenedit.debug.attemptTypeConversion = debugOld
	elseif nestedMetadata.isWrapper then -- unique_ptr etc.
		error("TODO")
	end
end

-- support vectors, lists, sets, maps etc.
-- obj == nil means that it's a static or global container
-- std::vector<std::vector<int>> vec ->
-- vec gets vector
-- vec[1] gets subvector
-- vec[1][2] gets int
-- value type can be class object:
-- std::vector<std::vector<ReflectionSampleStruct>> vec

-- std::map<std::string, std::vector<std::vector<ReflectionSampleStruct>>> map ->
-- map gets map
-- map["key"] gets vector
-- map["key"][1] gets subvector
-- map["key"][1][2] gets ReflectionSampleStruct

-- std::set<std::string> set ->
-- set gets set
-- set["key"] gets string
-- set.insert("key") inserts string, returns whether insertion took place (false if element already existed)
-- set["key"] = nil or false removes string, anything else inserts the element

-- store "container access path" in each one? like for map example above it would be {"key", 1, 2}
-- would need a way to get metadata of each returned element, so we can know if it's a container too and return reference to it
-- first level has to have C++ object as parent, next could have parent reference?

-- TODO: add support for const containers
-- "accessPath" contains all indexes accessed in sequence, needed to get from object to parent container
-- for example, for t[2].a[true][3] it would be {2, "a", true}, and 3 would be field name (t is an object)
-- for x[555][333] it would be {555}, and 333 would be field name (x is an object)

local function isAnyContainerOrWrapper(metadata)
	return metadata.type.isSequentialContainer or metadata.type.isAssociativeContainer or metadata.type.isWrapper
end

-- returns a copy of table with val inserted at the end
local function insertIntoTableCopy(t, val)
	local copy = table.copy(t)
	table.insert(copy, val)
	return copy
end

-- wraps a container field of class, class object, or global, so that it can be accessed as a table
-- FIELD NAME is always first-level name, not the last one which returns actual value!
local function getContainerReference(classObject, fieldName, accessPath)
	-- for now let's assume that there are no class types in containers, only primitive types
	accessPath = accessPath or {}
	local mt = {}
	local path
	if isClass(classObject) then
		path = format("[class field] %s::%s", getmetatable(classObject).name, fieldName)
	elseif isClassObject(classObject) then
		path = format("[class object field] %s::%s", getmetatable(classObject).className, fieldName)
	else
		path = format("[global] %s", fieldName)
	end
	local memberData = getEntityMetadataByPath(classObject, fieldName, accessPath)
	-- assume data.valueType contains nested type (for example std::vector<std::vector<int>> or std::reference_wrapper<std::vector<int>>)
	assert(memberData, format("'%s': Can't get metadata", path))
	function mt.__index(containerRef, key)
		-- associative containers can contain two nested types! FIXME
		-- return only type of value?
		local accessPath = insertIntoTableCopy(accessPath, key)
		local nestedData = getEntityMetadataByPath(classObject, fieldName, accessPath)
		if nestedData then
			if isAnyContainerOrWrapper(nestedData) then
				local nestedPath = insertIntoTableCopy(accessPath, key)
				return getContainerReference(classObject, fieldName, nestedPath)
			else
				-- TODO: get non-container field or class type
				error("TODO")
			end
		else -- not container and not wrapper - get actual value
			if memberData and memberData.isSequentialContainer and type(key) ~= "number" then
				error(format("'%s': Attempt to access sequential container with non-numeric key %q", path, key), 2)
			end
			local keys = containerRef:getKeys()
			if table.find(keys, key) then
				return api.getContainerElement(classObject, fieldName, accessPath)
			else
				error(format("'%s': Attempt to access container with invalid key %q", path, key), 2)
			end
		end
	end

	-- it would be more convenient to have this function be a closure inside __newindex, but then it would be recreated every time __newindex is called, which is not good
	local function trySetNoConvert(nestedPath, nestedData, value)
		if nestedData.isConst then
			error(format("'%s': Attempt to set const field %q", path, nestedData.name), 3)
		end
		local old = pgenedit.debug.attemptTypeConversion
		pgenedit.debug.attemptTypeConversion = false
		local converted = validateOrConvertParameter(value, nestedData, 1, path, true)
		pgenedit.debug.attemptTypeConversion = old
		if converted == nil then
			error(format("'%s': Attempt to set container with invalid value %q of type %q", path, value, type(value)), 3)
		else
			api.setContainerElement(classObject, fieldName, nestedPath, converted)
		end
	end

	function mt.__newindex(containerRef, key, value)
		local nestedPath = insertIntoTableCopy(accessPath, key)
		local nestedData = getEntityMetadataByPath(classObject, fieldName, nestedPath)
		if isAnyContainerOrWrapper(memberData) then
			if nestedData.isSequentialContainer or nestedData.isAssociativeContainer then
				if type(value) == "table" then -- accept only tables as values, because they are the only ones that can be sensibly converted to containers
					local nestedPath = insertIntoTableCopy(nestedPath, key)
					return assignTableToField(classObject, fieldName, nestedPath, value)
				else
					error(format("'%s': Attempt to set container with non-table value %q", path, value), 2)
				end
			elseif nestedData.isWrapper then
				error("TODO")
			elseif isClass(nestedData) then
				-- can't write to member class type
				error(format("'%s': Attempt to set class type %q", path, nestedData.name), 2)
			else
				trySetNoConvert(nestedPath, nestedData, value)
			end
		end
		if memberData.isSequentialContainer and type(key) ~= "number" then
			error(format("'%s': Attempt to set sequential container with non-numeric key %q", path, key), 2)
		end
		local keys = containerRef:getKeys()
		if table.find(keys, key) then
			trySetNoConvert(nestedPath, nestedData, value)
		else
			error(format("'%s': Attempt to set container with invalid key %q", path, key), 2)
		end
	end

	function mt.__len(ref)
		return api.getContainerSize(classObject, fieldName, accessPath)
	end

	local t = {}
	function t:clear()
		return api.clearContainer(classObject, fieldName, accessPath)
	end
	function t:size()
		return api.getContainerSize(classObject, fieldName, accessPath)
	end
	function t:getKeys()
		return api.getContainerKeys(classObject, fieldName, accessPath)
	end
	function t:getValues()
		return api.getContainerValues(classObject, fieldName, accessPath)
	end
	function t:enum()
		local keys = self:getKeys()
		return function(_, key)
			local keyIndex, key = next(keys, key)
			if key then
				return key, self[key]
			end
		end
	end
	function t:enumSorted()
		local keys = self:getKeys()
		table.sort(keys)
		return function(_, key)
			local keyIndex, key = next(keys, key)
			if key then
				return key, self[key]
			end
		end
	end
	local keys
	function mt:__call(_, k)
		if k == nil then
			keys = self:getKeys()
		end
		k = next(keys, k)
		if k then
			return k, self[k]
		end
	end

	return setmetatable(t, mt)
end

-- TODO: Boost.PP for easy & nice definition of accessor getters/setters (and other macros)
-- contrary to its name, for methods it uses rawset in addition to returning function, to cache the functions, because their creation might be expensive
-- as single table is used for all polymorphic objects, I can't use __index and __newindex metamethods to check for field existence, because I would have to call them manually from metatable (ugly)

local function currentOrInheritedMemberLookup(obj, key, className, treatAsClassName, shouldBeStatic)
	-- since treatAsClass is passed only for first function call, we don't need to check the object hierarchy validity in subsequent calls, as it's already checked
	if not treatAsClassName and getmetatable(obj).className ~= className and not isObjectOfClassOrDerived(obj, className) then
		error(format("Received object of type %q, expected %q", getmetatable(obj).className, className), 3)
	end
	local data = getmetatable(obj).classMetatable.getMemberData(key)
	local staticMatches = shouldBeStatic == nil or data.isStatic == shouldBeStatic
	if data.isField and staticMatches then -- current class has matching field
		if data.isContainer then
			return getContainerReference(obj, key)
		elseif data.type.isClass then -- class type other than container or wrapper
			return getmetatable(obj).classMetatable["?existingObjectAt"](api.getClassObjectFieldPtr(obj, className, key))
		else
			return api.getClassObjectField(obj, className, key)
		end
	elseif data.isCallable and staticMatches then -- current class has matching method
		local f = funcWrapper(className, key, data)
		-- rawset(obj, key, f) -- cache future accesses to methods
		return f
	else
		 -- recursively check base classes
		local bases = treatAsClassName and getmetatable(cpp.class[treatAsClassName]) or getmetatable(obj).classMetatable.bases
		for i, cls in ipairs(bases) do
			local val = currentOrInheritedMemberLookup(obj, key, className, cls, shouldBeStatic)
			if val ~= nil then -- if found, return the value
				return val
			end
			-- otherwise continue to next base class
		end
	end
end

-- now same as above, but for setting (__newindex), using behavior from below __newindex
-- returns if value was set somewhere in the hierarchy
local function currentOrInheritedMemberSet(obj, key, value, className, treatAsClassName, shouldBeStatic)
	if not treatAsClassName and getmetatable(obj).className ~= className and not isObjectOfClassOrDerived(obj, className) then
		error(format("Received object of type %q, expected %q", getmetatable(obj).className, className), 3)
	end
	local data = getmetatable(obj).classMetatable.getMemberData(key)
	if data.isConst then
		error(format("Attempt to set const field %q of class %q", key, className), 3)
	end
	local staticMatches = shouldBeStatic == nil or data.isStatic == shouldBeStatic
	if data.isField and staticMatches then -- class has field
		if isAnyContainerOrWrapper(data) then
			assignTableToField(obj, key, {}, value)
		elseif data.type.isClass then
			error(format("Attempt to set class-object field %q of class type %q", key, className), 3)
		else
			api.setClassObjectField(obj, className, key, value)
		end
		return true
	elseif data.isMethod and staticMatches then -- class has method
		error(format("Attempt to set method %q of class %q", key, className), 3)
	else
		-- recursively check base classes
		local bases = treatAsClassName and getmetatable(cpp.class[treatAsClassName]) or getmetatable(obj).classMetatable.bases
		for i, cls in ipairs(bases) do
			if currentOrInheritedMemberSet(obj, key, value, className, cls, shouldBeStatic) then
				return true
			end
			-- otherwise continue to next base class
		end
	end
end

-- creates metatable, which will be used to give object ability to access its fields and methods
local createObjectMetatable

-- call stack: user code -> pgenedit.class index -> makeClass -> createObjectMetatable
-- !!! if called from __index or __newindex of metatable, then stack is: user code -> our function (max 2 depth)

--[[local ]]function makeClass(className, ...)
	if className == nil then
		error("Class name is nil", 3)
	elseif not api.classExists(className) then
		error(format("Class %q does not exist", className), 3)
	end
	
	local classMT = {}
	classMT.name = className
	local info = api.getClassInfo(className)
	-- name, type, isConst, isReference, isPointer, isClass, isEnum, hasDefaultValue, defaultValue, isStatic, isField, isMethod, isCallable
	-- isCallable (for example std::function, functions as fields)
	-- returnType
	local members = info.members -- array of field properties
	classMT.bases = info.bases -- classes, which this class inherits from
	classMT.derived = info.derived -- classes, which inherit from this class
	classMT.members = members -- important that it happens before createObjectMetatable, as it uses members
	local function getMemberData(memberName)
		return members[memberName]
	end
	classMT.getMemberData = getMemberData

	local objMT = createObjectMetatable(classMT)
	classMT.objectMetatable = objMT
	local function new(...)
		-- TODO: find constructor matching parameters (count, types and possible conversions between types) and default arguments, if no matching constructor found, throw an error
		local obj = api.createObject(className, select("#", ...), ...)
		debug.setmetatable(obj, objMT) -- FIXME: you can't set a metatable of userdata without using debug library, so C++ needs to do it
		return obj
	end
	classMT.__call = function(cls, ...)
		return new(...)
	end
	classMT.new = new
	local function newExisting(ptr)
		assert(ptr ~= nil, "Pointer is nil")
		return setmetatable({["?ptr"] = ptr}, objMT)
	end

	local customIndexes =
	{
		new = new, -- this is without question mark, because it's restricted keyword in C++ anyways, probably should change this for consistency
		["?getMemberData"] = getMemberData,
		["?getMetadata"] = function() return info end,
		["?existingObjectAt"] = newExisting,
		["?members"] = members,
		["?bases"] = classMT.bases,
		["?derived"] = classMT.derived,
		["?info"] = info,
		["?name"] = className
	}

	-- static variables
	function classMT.__index(cls, str)
		-- handling this here, because I don't want to make overwriting the field possible
		if customIndexes[str] then
			return customIndexes[str]
		end
		local data = getMemberData(str)
		if not data then
			error(format("Attempt to access unknown static field %q of class %q", str, className), 2)
		end
		if data.isCallable and data.isStatic then
			local f = funcWrapper(className, str, data)
			--rawset(t, str, f)
			return f
		elseif not data.isCallable and data.isStatic then
			if isAnyContainerOrWrapper(data) then
				return getContainerReference(cls, str)
			elseif data.type.isClass then -- non-container-wrapper class
				return cpp.class[str]["?existingObjectAt"](api.getClassFieldPtr(className, str))
			else
				return api.getClassField(className, str)
			end
		else
			error(format("Attempt to access unknown static field %q of class %q", str, className), 2)
		end
	end
	function classMT.__newindex(t, key, value)
		local data = getMemberData(key)
		if not data then
			error(format("Attempt to set unknown static field %q of class %q", key, className), 2)
		end
		if data.isConst then
			error(format("Attempt to set const static field %q of class %q", key, className), 2)
		end
		-- changing callable members that aren't methods is not allowed, because they are not expecting possible lua errors/type differences from writing lua callback to be called from C++ via field
		assert(not data.isCallable, format("Attempt to set callable member %q of class %q", key, className), 2)
		if data.isStatic then
			api.setClassField(className, key, value)
		else
			error(format("Attempt to set unknown static field %q of class %q", key, className), 2)
		end
	end
	local class = {}
	function class.enum()
		return enumMembersGeneric(members, class, true)
	end
	function class.enumNoValues()
		return enumMembersGeneric(members, class, false)
	end
	return setmetatable(class, classMT)
end

--[[local ]]function createObjectMetatable(classMT)
	local objMT = {}
	local className = classMT.name
	objMT.className = className
	objMT.classMetatable = classMT

	-- so, value can be either userdata or table
	-- with userdata passing the objects to C++ is easy, with table it's not
	-- probably best way is to have "?ptr" field which C++ will use

	-- C++ side to receive object should:
	-- put pointer to int (or anything else) inside variant, with value equal to table field "?ptr"
	-- convert the pointer internally to pointer to object (might need writing custom converter)
	-- somehow dereference the pointer

	local customIndexes =
	{
		["?copy"] = function(obj)
			return obj.__copy()
		end,
		["?getMetadata"] = function(memberName)
			return classMT.getMemberData(memberName)
		end,
		["?isOfClassOrDerived"] = function(obj, className)
			return isObjectOfClassOrDerived(obj, className)
		end,
		["?className"] = className,
	}
	-- allows syntax such as obj["?copy"]() (without explicit argument)
	local function ooWrapper(obj)

	end
	function objMT.__index(obj, key)
		-- handling this here, because I don't want to make overwriting the field possible
		if customIndexes[key] then
			return customIndexes[key]
		end
		-- check for correct object type (inheritance won't change much, still original object is passed, just different metatable functions are called)
		local val = currentOrInheritedMemberLookup(obj, key, className)
		if val ~= nil then
			return val
		else
			error(format("Attempt to access unknown field %q of class %q", key, className), 2)
		end
	end

	function objMT.__newindex(obj, key, value)
		if not currentOrInheritedMemberSet(obj, key, value, className) then
			error(format("Attempt to set unknown field %q of class %q", key, className), 2)
		end
	end

	function objMT.__gc(obj)
		-- destroy only objects created by lua
		if type(obj) == "userdata" then
			api.destroyObject(obj)
		end
	end

	function objMT.__copy(this)
		local obj = api.copyObject(this)
		setmetatable(obj, objMT)
		return obj
	end
	-- TODO: dumpAllProperties (including functions shown clearly as such)

	function objMT.__tostring(obj)
		return format("%s: %s", className, api.getObjectAddress(obj))
	end

	-- enum members
	function objMT.__call(obj, _, k)
		k = next(classMT.members, k)
		if k then
			return k, obj[k], classMT.members[k]
		end
	end

	function objMT:enum()
		return enumMembersGeneric(classMT.members, self, true)
	end
	function objMT:enumNoValues()
		return enumMembersGeneric(classMT.members, self, false)
	end
	return objMT
end

do
	-- now global functions/variables
	local global = {}
	cpp.global = global
	local mt = {}
	setmetatable(global, mt)
	local members = api.getGlobalEnvironmentInfo()
	mt.members = members
	function global.enum() -- this can be called as global.enum(), because "enum" is a reserved keyword in C++
		return enumMembersGeneric(members, global, true)
	end
	function global.enumNoValues()
		return enumMembersGeneric(members, global, false)
	end
	local customIndexes = {
		["?getMemberData"] = function(memberName)
			return members[memberName]
		end,
		["?members"] = members
	}
	function mt.__index(t, key)
		if customIndexes[key] then
			return customIndexes[key]
		end
		local data = members[key]
		if not data then
			error(format("Attempt to access unknown global function/variable %q", key), 2)
		end
		if isAnyContainerOrWrapper(data) then
			return getContainerReference(nil, key)
		elseif data.type.isClass then -- non-container-wrapper class
			return cpp.class[key]["?existingObjectAt"](api.getGlobalPtr(key))
		elseif data.isCallable then
			local f = funcWrapper(nil, key, data)
			--rawset(t, key, f) -- commented out, because std::function fields might theoretically change their value
			-- FIXME: uncomment it, because as of now, function call wrapper uses not "captured function address" to call it, but the field itself, so rawset should work
			return f
		else
			return api.getGlobalField(key)
		end
	end

	function mt.__newindex(t, key, value)
		local data = members[key]
		if not data then
			error(format("Attempt to set unknown global function/variable %q", key), 2)
		end
		if data.isConst then
			error(format("Attempt to set const global function/variable %q", key), 2)
		end
		if data.isCallable then
			error(format("Attempt to set global callable %q", key), 2)
		end
		if isAnyContainerOrWrapper(data) then
			if type(value) == "table" then
				return assignTableToField(nil, key, {}, value)
			else
				error(format("Attempt to set global container %q with non-table value %q", key, value), 2)
			end
		elseif data.type.isClass then
			-- for now don't support assigning to class objects, because it would open a big can of worms regarding copy construction, copy assignment, etc.
			error(format("Attempt to set global class object %q", key), 2)
		else
			api.setGlobalField(key, value)
		end
	end

	-- enum members
	-- returns key, value, type metadata
	function mt.__call(_, _, k) -- args are: iterator function (table in this case), state (table) and key
		k = next(members, k)
		if k then
			return k, global[k], members[k]
		end
	end
end

-- tests
function tests()
	local stru = cpp.class.ReflectionSampleStruct.new()
	local errors = {}
	local function addError(level, fmt, ...)
		local info = debug.getinfo(level + 1, "l")
		local msg = format("[line %d]: ", info.currentline) .. format(fmt, ...)
		table.insert(errors, msg)
	end
	local function assert(cond, ...)
		if not cond then
			addError(2, ...)
		end
	end
	local function defCmp(a, b)
		return a == b
	end
	local function testGetProp(name, value, cmpFunc)
		local val = stru[name]
		cmpFunc = cmpFunc or defCmp
		if not cmpFunc(val, value) then
			addError(2, "stru.%s == %q, expected %q", name, val, value)
		end
	end
	local function testSetProp(name, value, cmpFunc)
		stru[name] = value
		cmpFunc = cmpFunc or defCmp
		local val = stru[name]
		if not cmpFunc(val, value) then
			addError(2, "stru.%s == %q, expected %q", name, val, value)
		end
	end

	local function cmpArrayVector(a, b)
		if #a ~= #b then
			return false
		end
		for i, v in ipairs(a) do
			if v ~= b[i] then
				return false
			end
		end
		return true
	end
	local function cmpAssociativeContainer(a, b)
		for k, v in pairs(a) do
			if v ~= b[k] then
				return false
			end
		end
		local countB = 0 -- "b" may have more or less keys than "a", of which all existing in "a" happen to compare equal
		for k, v in pairs(b) do
			countB = countB + 1
		end
		return countB == #a
	end
	local function mmv(a, b, c)
		local v = select(mmv - 5, a, b, c)
		_G.assert(v ~= nil)
		return v
	end
	-- TODO: test field properties

	-- get/set property tests
	testGetProp("i", 0)
	testGetProp("str", "default")
	testSetProp("i", 1)
	testSetProp("str", "test")
	testSetProp("i", 837248237)
	testSetProp("str", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaatest")
	testGetProp("vec", {1, 2, 3}, cmpArrayVector)
	testGetProp("arr", {1, 2, 3, 4, 5}, cmpArrayVector)
	testGetProp("map", {a = 1, b = 2, c = 3}, cmpAssociativeContainer)
	-- TODO: implement sets: testGetProp("set", {1, 2, 3}, cmpAssociativeContainer)
	testSetProp("vec", {4, 5, 6}, cmpArrayVector)
	testSetProp("arr", {6, 5, 4, 3, 2}, cmpArrayVector)
	testSetProp("map", {a = 3, b = 2, c = 1}, cmpAssociativeContainer)
	testSetProp("map", {akey = 4434, bkey = 5525, ckey = 66536}, cmpAssociativeContainer)
	-- TODO: map test with different key/value types

	-- test different instance
	local struOld = stru
	stru = cpp.class.ReflectionSampleStruct() -- use call syntax for object creation
	testGetProp("i", 0)
	testGetProp("str", "default")
	testGetProp("vec", {1, 2, 3}, cmpArrayVector)
	testGetProp("arr", {1, 2, 3, 4, 5}, cmpArrayVector)
	testGetProp("map", {a = 1, b = 2, c = 3}, cmpAssociativeContainer)
	stru = struOld

	-- function call tests

	stru:modifyMultiple(3, "cddd", {5, 6})
	testGetProp("i", 3)
	testGetProp("str", "cddd")
	testGetProp("vec", {5, 6})
	-- adds or inserts
	stru:modifyMultipleByOperation(88, "ap", {1})
	testGetProp("i", 91)
	testGetProp("str", "cdddap")
	testGetProp("vec", {5, 6, 1})

	assert(stru:get5() == 5, "[1st] stru:get5() == %d, expected 5", stru:get5())
	assert(stru:get5() == 5, "[2nd] stru:get5() == %d, expected 5", stru:get5())

	-- globals
	local global = cpp.global
	-- static int __declspec(naked) __fastcall fastcallGlobalFunctionTest(int argEcx, int argEdx, int argEsp)
	-- has to have values 0x77777777, 0x3333333, 0x88888888
	-- returns index of first nonmatching argument or 0 if all match
	local function fastcallGlobalFunctionTest(argEcx, argEdx, argEsp)
		return global.fastcallGlobalFunctionTest(argEcx, argEdx, argEsp)
	end
	assert(fastcallGlobalFunctionTest(0x77777777, 0x3333333, 0x88888888) == 0, "fastcallGlobalFunctionTest(0x77777777, 0x3333333, 0x88888888) == %d, expected 0", fastcallGlobalFunctionTest(0x77777777, 0x3333333, 0x88888888))
	assert(fastcallGlobalFunctionTest(0x0, 0x1, 0x2) == 1, "fastcallGlobalFunctionTest(0x0, 0x1, 0x2) == %d, expected 1", fastcallGlobalFunctionTest(0x0, 0x1, 0x2))
	assert(fastcallGlobalFunctionTest(0x77777777, 0x0, 0x2) == 2, "fastcallGlobalFunctionTest(0x77777777, 0x0, 0x2) == %d, expected 2", fastcallGlobalFunctionTest(0x77777777, 0x0, 0x2))
	assert(fastcallGlobalFunctionTest(0x77777777, 0x3333333, 0x0) == 3, "fastcallGlobalFunctionTest(0x77777777, 0x3333333, 0x0) == %d, expected 3", fastcallGlobalFunctionTest(0x77777777, 0x3333333, 0x0))
	local MMVER = global.MMVER
	assert(MMVER == Game.Version, "MMVER == %d, expected %d", MMVER, Game.Version)
	local inGame = global.inGame
	assert(inGame == internal.InGame, "inGame == %s, expected %s", tostring(inGame), tostring(internal.InGame))
	local playersFullArray = global.PlayersFullArray
	for i = 0, Game.PlayersArray.Count do
		assert(playersFullArray[i] == Game.PlayersArray[i], "playersFullArray[%d] == %s, expected %s", i, tostring(playersFullArray[i]), tostring(Game.PlayersArray[i]))
	end

	-- throw error tests
	local function shouldThrow(func, condStr, ...)
		local ok = pcall(func, ...)
		if ok then
			assert("%q did not throw an error", func, condStr)
		end
	end

	-- getting/setting nonexisting properties should throw error
	shouldThrow(function() local v = stru.nonexisting end, "stru.nonexisting")
	shouldThrow(function() stru.nonexisting = 1 end, "stru.nonexisting = 1")
	-- reassigning functions should throw error
	shouldThrow(function() stru.get5 = 1 end, "stru.get5 = 1")
	shouldThrow(function() stru.modifyMultiple = function() end end, "stru.modifyMultiple = function() end")

	-- assignment to array which changes amount of elements should throw lua error
	shouldThrow(function() stru.arr = {1, 2, 3, 4, 5, 6, 7, 8} end, "stru.arr = {1, 2, 3, 4, 5, 6, 7, 8}")
	-- can't define new globals
	shouldThrow(function() global.newGlobal = 1 end, "global.newGlobal = 1")
	-- or get values of nonexisting globals
	shouldThrow(function() local v = global.newGlobal end, "global.newGlobal")
	-- can't get classes as globals
	shouldThrow(function() local v = global.ReflectionSampleStruct end, "global.ReflectionSampleStruct")
	-- or set them
	shouldThrow(function() global.ReflectionSampleStruct = 1 end, "global.ReflectionSampleStruct = 1")
	inGame = internal.InGame
	-- setting invalid value types should throw error
	shouldThrow(function() global.inGame = 1 end, "global.inGame = 1")
	shouldThrow(function() global.inGame = "test" end, "global.inGame = \"test\"")
	global.inGame = inGame -- just in case, restore original value

	-- test inner classes
	-- indexing a class field which is another class should return a table type with "?ptr" set
	local innerStruct = stru.innerStruct
	assert(type(innerStruct) == "table", "type(innerStruct) == %q, expected %q", type(innerStruct), "table")
	assert(type(innerStruct["?ptr"]) == "number", "type(innerStruct[\"?ptr\"]) == %q, expected %q", type(innerStruct["?ptr"]), "number")
	assert(innerStruct["?ptr"] ~= 0, "innerStruct[\"?ptr\"] == %d, expected nonzero", innerStruct["?ptr"])
	assert(getmetatable(innerStruct).className == "InnerStruct", "getmetatable(innerStruct).className == %q, expected %q", getmetatable(innerStruct).className, "InnerStruct")

	--[[
		struct InnerStruct
{
    bool b, bb, bbb;
    std::string str;
    void allTrue()
    {
        b = true, bb = true, bbb = true;
    }
    void allFalse()
    {
        b = false, bb = false, bbb = false;
    }

    InnerStruct() : b(false), bb(false), bbb(false), str("default") {}
    // default copy ctor
    InnerStruct(const InnerStruct&) = default;
    InnerStruct(InnerStruct&&) = default;
    InnerStruct& operator=(const InnerStruct&) = default;
    InnerStruct& operator=(InnerStruct&&) = default;

    // virtual methods
    virtual int returnSizeof() const
    {
        return sizeof(InnerStruct);
    }

    // in derived class will return double the value
    virtual int addAllArguments(int a, int b, int c, int d) const
    {
        return a + b + c + d;
    }

    // an operator which modifies the struct based on int argument passed to it
    InnerStruct& operator+=(int val)
    {
        str += std::to_string(val);
        return *this;
    }

    InnerStruct operator+(int val) const
    {
        InnerStruct u2(*this);
        u2.str += std::to_string(val);
        return u2;
    }

    friend std::string to_string(const InnerStruct& u);

    // comparison operator for all fields
    bool operator==(const InnerStruct& other) const
    {
        return b == other.b && bb == other.bb && bbb == other.bbb && str == other.str;
    }

    RTTR_ENABLE()
};
	]]
	local struOld = stru
	stru = innerStruct
	testGetProp("b", false)
	testGetProp("bb", false)
	stru:allTrue()
	testGetProp("b", true)
	testGetProp("bb", true)
	testGetProp("bbb", true)
	testSetProp("b", false)
	stru:allFalse()
	testGetProp("b", false)
	testGetProp("bb", false)
	testGetProp("str", "default")
	testSetProp("str", "test")
	testGetProp("str", "test")
	assert(stru:addAllArguments(1, 2, 3, 4) == 10, "stru:addAllArguments(1, 2, 3, 4) == %d, expected 10", stru:addAllArguments(1, 2, 3, 4))

	--[[
		// few constructors with default arguments
ReflectionSampleStruct(bool b, int i = 20, char ch = 'a') : ReflectionSampleStruct() // this call also initializes other fields with default values
{
    this->i = i + b;
    str = std::string(1, ch);
    vec = { 1, 2, 3 };
    arr = { 1, 2, 3, 4, 5 };
    map = { {"a", 1}, {"b", 2}, {"c", 3} };
    u = { 0 };
}

ReflectionSampleStruct(int a, int b, int c = 5, int d = 20) : ReflectionSampleStruct()
{
    i = a + b + c + d;
    str = "default";
    vec = { 1, 2, 3 };
    arr = { 1, 2, 3, 4, 5 };
    map = { {"a", 1}, {"b", 2}, {"c", 3} };
    u = { 0 };
}
	]]
	stru = cpp.class.ReflectionSampleStruct.new(true)
	testGetProp("i", 21)
	testGetProp("str", "a")
	testGetProp("vec", {1, 2, 3}, cmpArrayVector)
	stru = cpp.class.ReflectionSampleStruct.new(false, 5)
	testGetProp("i", 5)
	testGetProp("str", "a")
	-- the other constructor
	stru = cpp.class.ReflectionSampleStruct.new(1, 2)
	testGetProp("i", 28)
	testGetProp("str", "default")

	stru = cpp.class.ReflectionSampleStruct.new(2, 3, 4)
	testGetProp("i", 29)
	stru = cpp.class.ReflectionSampleStruct.new(2, 3, 4, 5)
	testGetProp("i", 14)
	-- more arguments should throw
	shouldThrow(function() stru = cpp.class.ReflectionSampleStruct.new(2, 3, 4, 5, 6) end, "cpp.class.ReflectionSampleStruct.new(2, 3, 4, 5, 6)")

	stru = struOld

	-- void setArrayWithDefaultArgs(int a, int b, int c = 12, int d = 33, int e = -5)
	stru:setArrayWithDefaultArgs(1, 2)
	testGetProp("arr", {1, 2, 12, 33, -5}, cmpArrayVector)
	stru:setArrayWithDefaultArgs(1, 2, 3)
	testGetProp("arr", {1, 2, 3, 33, -5}, cmpArrayVector)

	local inner = cpp.class.InnerStruct.new()
	local inner2 = cpp.class.InnerStruct2.new()

	-- basic virtual function test, TODO: more complex tests
	assert(inner:returnSizeof() ~= inner2:returnSizeof(), "inner:returnSizeof() == %d, inner2:returnSizeof() == %d, expected different values", inner:returnSizeof(), inner2:returnSizeof())
	-- derived class "addAllArguments" should return double the value
	assert(inner:addAllArguments(1, 2, 3, 4) == 10, "inner:addAllArguments(1, 2, 3, 4) == %d, expected 10", inner:addAllArguments(1, 2, 3, 4))
	assert(inner2:addAllArguments(1, 2, 3, 4) == 20, "inner2:addAllArguments(1, 2, 3, 4) == %d, expected 20", inner2:addAllArguments(1, 2, 3, 4))

	-- basic inheritance test
	-- inner2 should have members and methods of inner
	struOld = stru
	stru = inner2
	testGetProp("b", false)
	testGetProp("bb", false)
	stru:allTrue()
	testGetProp("b", true)
	testGetProp("bb", true)
	testGetProp("bbb", true)
	stru = struOld

	-- static property tests
	--[[
		static int staticInt;
		static void* staticPtr;
		static const char* const staticReadonlyPchar; // "staticReadonlyPcharText"
		static UnionSample staticUnionsArr[3];
		static std::array<UnionSample, 3> staticUnionsArrStd;
	]]
	local cls = cpp.class.ReflectionSampleStruct
	local pcharData = cls["?getMemberData"]("staticReadonlyPchar")
	assert(pcharData.isField, "pcharData.isField == %s, expected true", tostring(pcharData.isField))
	assert(pcharData.isStatic, "pcharData.isStatic == %s, expected true", tostring(pcharData.isStatic))
	assert(not pcharData.isCallable, "pcharData.isCallable == %s, expected false", tostring(pcharData.isCallable))
	assert(pcharData.isConst, "pcharData.isConst == %s, expected true", tostring(pcharData.isConst))
	assert(pcharData.type.isPointer, "pcharData.type.isPointer == %s, expected true", tostring(pcharData.type.isPointer))
	assert(cls.staticReadonlyPchar == "staticReadonlyPcharText", "cls.staticReadonlyPchar == %q, expected %q", cls.staticReadonlyPchar, "staticReadonlyPcharText")
	cls.staticReadonlyPchar = "test34325"
	assert(cls.staticReadonlyPchar == "test34325", "cls.staticReadonlyPchar == %q, expected %q", cls.staticReadonlyPchar, "test34325")
	assert(cls["?getMemberData"]("staticPtr").name == "staticPtr", "cls[\"?getMemberData\"](\"staticPtr\").name == %q, expected %q", cls["?getMemberData"]("staticPtr").name, "staticPtr")
	cls.staticPtr = 0x50647480
	assert(cls.staticPtr == 0x50647480, "cls.staticPtr == %d, expected %d", cls.staticPtr, 0x50647480)
	assert(cls.isPointer, "cls.isPointer == %s, expected true", tostring(cls.isPointer))
end