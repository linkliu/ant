#include "imgui_lua_util.h"
#include "backend/imgui_impl_bgfx.h"
#include <bee/nonstd/unreachable.h>
#include <stdint.h>

namespace imgui_lua::wrap_ImGuiInputTextCallbackData {
    void pointer(lua_State* L, ImGuiInputTextCallbackData& v);
}

namespace imgui_lua::util {

static lua_CFunction str_format = NULL;

lua_Integer field_tointeger(lua_State* L, int idx, lua_Integer i) {
    lua_geti(L, idx, i);
    auto v = luaL_checkinteger(L, -1);
    lua_pop(L, 1);
    return v;
}

lua_Number field_tonumber(lua_State* L, int idx, lua_Integer i) {
    lua_geti(L, idx, i);
    auto v = luaL_checknumber(L, -1);
    lua_pop(L, 1);
    return v;
}

bool field_toboolean(lua_State* L, int idx, lua_Integer i) {
    lua_geti(L, idx, i);
    bool v = !!lua_toboolean(L, -1);
    lua_pop(L, 1);
    return v;
}

ImTextureID get_texture_id(lua_State* L, int idx) {
    int lua_handle = (int)luaL_checkinteger(L, idx);
    if (auto id = ImGui_ImplBgfx_GetTextureID(lua_handle)) {
        return *id;
    }
    luaL_error(L, "Invalid handle type TEXTURE");
    std::unreachable();
}

const char* format(lua_State* L, int idx) {
    lua_pushcfunction(L, str_format);
    lua_insert(L, idx);
    lua_call(L, lua_gettop(L) - idx, 1);
    return lua_tostring(L, -1);
}

static void* strbuf_realloc(lua_State *L, void *ptr, size_t osize, size_t nsize) {
    void *ud;
    lua_Alloc allocator = lua_getallocf(L, &ud);
    return allocator(ud, ptr, osize, nsize);
}

static int strbuf_assgin(lua_State* L) {
    auto sbuf = (strbuf*)lua_touserdata(L, 1);
    size_t newsize = 0;
    const char* newbuf = luaL_checklstring(L, 2, &newsize);
    newsize++;
    if (newsize > sbuf->size) {
        sbuf->data = (char *)strbuf_realloc(L, sbuf->data, sbuf->size, newsize);
        sbuf->size = newsize;
    }
    memcpy(sbuf->data, newbuf, newsize);
    return 0;
}

static int strbuf_resize(lua_State* L) {
    auto sbuf = (strbuf*)lua_touserdata(L, 1);
    size_t newsize = (size_t)luaL_checkinteger(L, 2);
    sbuf->data = (char *)strbuf_realloc(L, sbuf->data, sbuf->size, newsize);
    sbuf->size = newsize;
    return 0;
}

static int strbuf_tostring(lua_State* L) {
    auto sbuf = (strbuf*)lua_touserdata(L, 1);
    lua_pushstring(L, sbuf->data);
    return 1;
}

static int strbuf_release(lua_State* L) {
    auto sbuf = (strbuf*)lua_touserdata(L, 1);
    strbuf_realloc(L, sbuf->data, sbuf->size, 0);
    sbuf->data = NULL;
    sbuf->size = 0;
    return 0;
}

static constexpr size_t kStrBufMinSize = 256;

strbuf* strbuf_create(lua_State* L, int idx) {
    size_t sz;
    const char* text = lua_tolstring(L, idx, &sz);
    auto sbuf = (strbuf*)lua_newuserdatauv(L, sizeof(strbuf), 0);
    if (text == NULL) {
        sbuf->size = kStrBufMinSize;
        sbuf->data = (char *)strbuf_realloc(L, NULL, 0, sbuf->size);
        sbuf->data[0] = '\0';
    } else {
        sbuf->size = (std::max)(sz + 1, kStrBufMinSize);
        sbuf->data = (char *)strbuf_realloc(L, NULL, 0, sbuf->size);
        memcpy(sbuf->data, text, sz + 1);
    }
    if (luaL_newmetatable(L, "ImGui::StringBuf")) {
        lua_pushcfunction(L, strbuf_tostring);
        lua_setfield(L, -2, "__tostring");
        lua_pushcfunction(L, strbuf_release);
        lua_setfield(L, -2, "__gc");
        static luaL_Reg l[] = {
            { "Assgin", strbuf_assgin },
            { "Resize", strbuf_resize },
            { NULL, NULL },
        };
        luaL_newlib(L, l);
        lua_setfield(L, -2, "__index");
    }
    lua_setmetatable(L, -2);
    return sbuf;
}

strbuf* strbuf_get(lua_State* L, int idx) {
    if (lua_type(L, idx) == LUA_TUSERDATA) {
        auto sbuf = (strbuf*)luaL_checkudata(L, idx, "ImGui::StringBuf");
        return sbuf;
    }
    luaL_checktype(L, idx, LUA_TTABLE);
    int t = lua_geti(L, idx, 1);
    if (t != LUA_TSTRING && t != LUA_TNIL) {
        auto sbuf = (strbuf*)luaL_checkudata(L, -1, "ImGui::StringBuf");
        lua_pop(L, 1);
        return sbuf;
    }
    auto sbuf = strbuf_create(L, -1);
    lua_replace(L, -2);
    lua_seti(L, idx, 1);
    return sbuf;
}

int input_callback(ImGuiInputTextCallbackData* data) {
    auto ctx = (input_context*)data->UserData;
    lua_State* L = ctx->L;
    lua_pushvalue(L, ctx->callback);
    wrap_ImGuiInputTextCallbackData::pointer(L, *data);
    if (lua_pcall(L, 1, 1, 0) != LUA_OK) {
        return 1;
    }
    lua_Integer retval = lua_tointeger(L, -1);
    lua_pop(L, 1);
    return (int)retval;
}

void create_table(lua_State* L, std::span<TableInteger> l) {
    lua_createtable(L, 0, (int)l.size());
    for (auto const& e : l) {
        lua_pushinteger(L, e.value);
        lua_setfield(L, -2, e.name);
    }
}

void set_table(lua_State* L, std::span<TableAny> l) {
    for (auto const& e : l) {
        e.value(L);
        lua_setfield(L, -2, e.name);
    }
}

static void set_table(lua_State* L, std::span<luaL_Reg> l, int nup) {
    luaL_checkstack(L, nup, "too many upvalues");
    for (auto const& e : l) {
        for (int i = 0; i < nup; i++) {
            lua_pushvalue(L, -nup);
        }
        lua_pushcclosure(L, e.func, nup);
        lua_setfield(L, -(nup + 2), e.name);
    }
    lua_pop(L, nup);
}

static const char *
next_key(lua_State *L, const char *keys) {
	while (*keys == '|')
		++keys;
	const char *p = keys;
	while (*p != '|' && *p != 0)
		++p;
	lua_pushlstring(L, keys, p-keys);
	return p;
}

static int
cache_flags(lua_State *L) {
	lua_pushvalue(L, 1);
	if (lua_gettable(L, lua_upvalueindex(1)) == LUA_TNUMBER) {
		return 1;
	}
	lua_pop(L, 1);
	const char *keys = lua_tostring(L, 1);
	int r = 0;
	while (keys[0]) {
		const char *next_keys = next_key(L, keys);
		if (lua_gettable(L, lua_upvalueindex(1)) != LUA_TNUMBER) {
			next_key(L, keys);
			return luaL_error(L, "Invalid flag %s.%s", lua_tostring(L, lua_upvalueindex(2)), lua_tostring(L, -1));
		}
        lua_Integer v = lua_tointeger(L, -1);
        lua_pop(L, 1);
        r |= v;
		keys = next_keys;
	}
    lua_pushinteger(L, r);
	lua_settable(L, lua_upvalueindex(1));
    lua_pushinteger(L, r);
    return 1;
}

static int make_flags(lua_State* L) {
	int t = lua_type(L, 1);
	if (t == LUA_TSTRING) {
		return cache_flags(L);
	} else if (t != LUA_TTABLE) {
		return luaL_error(L, "flags should be table or string");
	}
    int i;
    lua_Integer r = 0;
    for (i = 1; (t = lua_geti(L, 1, i)) != LUA_TNIL; i++) {
        if (t != LUA_TSTRING)
            luaL_error(L, "Flag name should be string, it's %s", lua_typename(L, t));
        if (lua_gettable(L, lua_upvalueindex(1)) != LUA_TNUMBER) {
            lua_geti(L, 1, i);
            luaL_error(L, "Invalid flag %s.%s", lua_tostring(L, lua_upvalueindex(2)), lua_tostring(L, -1));
        }
        lua_Integer v = lua_tointeger(L, -1);
        lua_pop(L, 1);
        r |= v;
    }
    lua_pushinteger(L, r);
    return 1;
}

void struct_gen(lua_State* L, const char* name, std::span<luaL_Reg> funcs, std::span<luaL_Reg> setters, std::span<luaL_Reg> getters) {
    lua_newuserdatauv(L, sizeof(uintptr_t), 0);
    int ud = lua_gettop(L);
    lua_newtable(L);
    if (!setters.empty()) {
        static lua_CFunction setter_func = +[](lua_State* L) {
            lua_pushvalue(L, 2);
            if (LUA_TNIL == lua_gettable(L, lua_upvalueindex(1))) {
                return luaL_error(L, "%s.%s is invalid.", lua_tostring(L, lua_upvalueindex(2)), lua_tostring(L, 2));
            }
            lua_pushvalue(L, 3);
            lua_call(L, 1, 0);
            return 0;
        };
        lua_createtable(L, 0, (int)setters.size());
        lua_pushvalue(L, ud);
        set_table(L, setters, 1);
        lua_pushstring(L, name);
        lua_pushcclosure(L, setter_func, 2);
        lua_setfield(L, -2, "__newindex");
    }
    if (!funcs.empty()) {
        lua_createtable(L, 0, (int)funcs.size());
        lua_pushvalue(L, ud);
        set_table(L, funcs, 1);
        lua_newtable(L);
    }
    static lua_CFunction getter_func = +[](lua_State* L) {
        lua_pushvalue(L, 2);
        if (LUA_TNIL == lua_gettable(L, lua_upvalueindex(1))) {
            return luaL_error(L, "%s.%s is invalid.", lua_tostring(L, lua_upvalueindex(2)), lua_tostring(L, 2));
        }
        lua_call(L, 0, 1);
        return 1;
    };
    lua_createtable(L, 0, (int)getters.size());
    lua_pushvalue(L, ud);
    set_table(L, getters, 1);
    lua_pushstring(L, name);
    lua_pushcclosure(L, getter_func, 2);
    lua_setfield(L, -2, "__index");
    if (!funcs.empty()) {
        lua_setmetatable(L, -2);
        lua_setfield(L, -2, "__index");
    }
    lua_setmetatable(L, -2);
}

void flags_gen(lua_State* L, const char* name) {
    lua_pushstring(L, name);
    lua_pushcclosure(L, make_flags, 2);
}

void init(lua_State* L) {
    luaopen_string(L);
    lua_getfield(L, -1, "format");
    str_format = lua_tocfunction(L, -1);
    lua_pop(L, 2);
}

}
