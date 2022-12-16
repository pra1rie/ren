import std.stdio;
import std.string : toStringz;
import std.file : exists, isDir, readText;
import std.array : split, join;
import std.algorithm : canFind, each;
import std.conv : to;
import std.process : spawnShell, wait;
import core.stdc.stdlib : exit;

import ren_scancodes;
import salka;

import derelict.sdl2.sdl;
import derelict.sdl2.ttf;

// can't i use nara?
// also can this be done in C?

string path;

void fail(string err)
{
	stderr.writeln("FAIL: " ~ err);
	exit(1);
}

void warn(string err)
{
	stderr.writeln("WARN: " ~ err);
}

SDL_Scancode[] ignoredKeys = [
	SDL_SCANCODE_LSHIFT,
	SDL_SCANCODE_LCTRL,
	SDL_SCANCODE_LALT,
	SDL_SCANCODE_LGUI,
	SDL_SCANCODE_RSHIFT,
	SDL_SCANCODE_RCTRL,
	SDL_SCANCODE_RALT,
	SDL_SCANCODE_RGUI,
	SDL_SCANCODE_MENU,
	SDL_SCANCODE_TAB,
	SDL_SCANCODE_CAPSLOCK,
	SDL_SCANCODE_RETURN,
	SDL_SCANCODE_COMPUTER,
];

class Font {
	int size;
	SDL_Rect rect;
	private TTF_Font *_font;
	private SDL_Surface *_surf;
	private SDL_Texture *_text;

	this(string t_path, int t_size)
	{
		_font = TTF_OpenFont(t_path.toStringz, t_size);
		size = t_size;
		rect = SDL_Rect(0, 0, size, size);
	}

	void write(string text, int[2] pos, ubyte[3] col = [240, 240, 240])
	{
		if (text == "") return;
		renderTextToMySurface(text, col);
		rect = SDL_Rect(pos[0], pos[1], _surf.w, _surf.h);
		renderAndFreeMyTexture();
	}

	void writeCentered(string text, int[2] pos, ubyte[3] col = [240, 240, 240])
	{
		if (text == "") return;
		renderTextToMySurface(text, col);
		rect = SDL_Rect(
				pos[0] - (_surf.w/2),
				pos[1] - (_surf.h/2),
				_surf.w,
				_surf.h
			);
		renderAndFreeMyTexture();
	}
	
	void writeRight(string text, int[2] pos, ubyte[3] col = [240, 240, 240])
	{
		if (text == "") return;
		renderTextToMySurface(text, col);
		rect = SDL_Rect(
				pos[0] - _surf.w,
				pos[1],
				_surf.w,
				_surf.h
			);
		renderAndFreeMyTexture();
	}

	private void renderAndFreeMyTexture()
	{
		SDL_RenderCopy(ren.render, _text, null, &rect);
		SDL_FreeSurface(_surf);
		SDL_DestroyTexture(_text);
	}

	private void renderTextToMySurface(string text, ubyte[3] col)
	{
		// getting colours
		SDL_Color c0 = SDL_Color(col[0], col[1], col[2]);
		SDL_Color c1;
		SDL_GetRenderDrawColor(ren.render, &c1.r, &c1.g, &c1.b, null);

		// rendering text to a surface
		_surf = TTF_RenderText_Shaded(_font, text.toStringz, c0, c1);
		// creating a texture from that surface
		_text = SDL_CreateTextureFromSurface(ren.render, _surf);
	}
}

struct Cmd {
	string name;
	string cmd;
	int key;
	string key_name;
}

// uh i could use SDL_Color, right? right?
struct theme {
static:
	ubyte[3] background;
	ubyte[3] command;
	ubyte[3] text;
	ubyte[3] key;
}

static struct ren {
static:
	SDL_Window *window;
	SDL_Renderer *render;
	int[2] windowSize;
	string windowTitle;
	int fontSize;
	string fontPath;
	int scroll;
	int spacing;
	bool isScrolling;
	bool exitOnKey;
	Font font;
	Cmd[] cmds;
}

bool getKey(SDL_Scancode key)
{
	const ubyte *state = SDL_GetKeyboardState(null);
	return state[key] != 0;
}

void events()
{
	// eventsing
	SDL_Event e;
	if (SDL_PollEvent(&e)) {
		switch (e.type) {
			case SDL_QUIT: {
				quit();
				break;
			}
			case SDL_WINDOWEVENT: {
				if (e.window.event == SDL_WINDOWEVENT_RESIZED) {
					ren.windowSize = [e.window.data1, e.window.data2];
				}
				break;
			}
			case SDL_MOUSEWHEEL: {
				ren.scroll -= e.wheel.y;
				if (ren.scroll < 0) ren.scroll = 0;
				break;
			}
			case SDL_KEYUP: {
				auto key = e.key.keysym.scancode;
				if (key == SDL_SCANCODE_LSHIFT)
					ren.isScrolling = false;
				break;
			}
			case SDL_KEYDOWN: {
				auto key = e.key.keysym.scancode;
				if (key == SDL_SCANCODE_ESCAPE)
					quit();

				// scrolling
				if (key == SDL_SCANCODE_LSHIFT)
					ren.isScrolling = true;

				if (ren.isScrolling) {
					if (key == SDL_SCANCODE_DOWN) {
						++ren.scroll;
					}
					if (key == SDL_SCANCODE_UP) {
						if (--ren.scroll < 0)
							ren.scroll = 0;
					}
				}

				// cmd keys
				if (ignoredKeys.canFind(key)) break;

				foreach (cmd; ren.cmds) {
					if (key == cmd.key) {
						spawnShell(cmd.cmd ~ " &").wait;
						if (ren.exitOnKey)
							quit();
					}
				}
				break;
			}
			default: break;
		}
	}
}

void update()
{
	SDL_SetRenderDrawColor(ren.render,
			theme.background[0], theme.background[1], theme.background[2], 0);
	SDL_RenderClear(ren.render);
	
	// TODO: no need to draw outside screen

	for (int i = 0; i < ren.cmds.length; ++i) {
		// write key
		ren.font.writeRight(" [" ~ ren.cmds[i].key_name ~ "] ",
				[
					ren.windowSize[0],
					ren.spacing + (i - ren.scroll) * (ren.font.size + ren.spacing)
				], theme.key);

		// write command
		ren.font.writeRight(ren.cmds[i].cmd,
				[
					ren.windowSize[0] - ren.font.rect.w,
					ren.spacing + (i - ren.scroll) * (ren.font.size + ren.spacing)
				], theme.command);
	
		// write name
		ren.font.write(" " ~ ren.cmds[i].name,
				[
					0,
					ren.spacing + (i - ren.scroll) * (ren.font.size + ren.spacing)
				], theme.text);
	}

	SDL_RenderPresent(ren.render);
}

ubyte hexToDec(string col)
{
	// bruh.
	ubyte res = 0;
	for (size_t i = 0; i < col.length; ++i) {
		auto j = (col.length-1) - i;
		if (col[j] >= 'a' && col[j] <= 'f') {
			res += (col[j] - 'a' + 10) * (16 ^^ i);
		}
		else if (col[j] >= '0' && col[j] <= '9') {
			res += (col[j] - '0') * (16 ^^ i);
		}
		else {
			fail("Invalid color: " ~ col);
		}
	}
	return res;
}

ubyte[3] getTheme(Obj[string] vars, string key, ubyte[3] res)
{
	ubyte[3] color;
	if (key in vars) {
		auto col = vars[key];

		if (col.type == ObjType.STRING) {
			if (col.base.length < 6) {
				warn("Invalid color: " ~ col.getObj);
				return res;
			}

			auto offset = (col.base[0] == '#')? 1 : 0;
			color = [
				hexToDec(col.base[0+offset..2+offset]),
				hexToDec(col.base[2+offset..4+offset]),
				hexToDec(col.base[4+offset..6+offset]),
			];
			return color;
		}

		if (col.type != ObjType.LIST || col.list.length < 3) {
			warn("Invalid color: " ~ col.getObj);
			return res;
		}
		
		foreach (i; 0..3) {
			if (!isNumber(col.list[i].getObj)) {
				warn("Invalid digit: " ~ col.list[i].getObj);
				return res;
			}

			color[i] = to!ubyte(col.list[i].getObj);
		}
		return color;
	}

	return res;
}

void loadConfigFile(string path)
{
	auto cfg = loadConfig(path);
	if (!("commands" in cfg))
		fail("Variable does not exist: commands");
	if (cfg["commands"].type != ObjType.LIST)
		fail("Variable must be a list");

	foreach (item; cfg["commands"].list) {
		if (item.list.length != 3)
			fail("Invalid command: " ~ item.getObj);

		if (!isNumber(item.list[2].base) && !(item.list[2].base in scancodes))
			fail("Invalid key: " ~ item.list[2].base);

		int key = (item.list[2].base.isNumber)?
				to!int(item.list[2].base) : scancodes[item.list[2].base];

		ren.cmds ~= Cmd(item.list[0].base, item.list[1].base, key, item.list[2].base);
	}

	// exit on key (on by default)
	ren.exitOnKey = true;
	if ("exit-on-key" in cfg) {
		if (!isNumber(cfg["exit-on-key"].getObj))
			fail("Invalid digit: " ~ cfg["exit-on-key"].getObj);
		ren.exitOnKey = (cfg["exit-on-key"].getObj != "0");
	}

	// text spacing
	ren.scroll = 0;
	ren.spacing = 3;

	if ("spacing" in cfg) {
		if (!isNumber(cfg["spacing"].getObj))
			fail("Invalid digit: " ~ cfg["spacing"].getObj);
		ren.spacing = to!int(cfg["spacing"].getObj);
	}

	int w = 640, h = 0;
	ren.fontSize = 0;
	ren.fontPath = "font.ttf";

	// font
	if ("font-path" in cfg) {
		if (cfg["font-path"].type != ObjType.STRING)
			fail("Invalid string: " ~ cfg["font-path"].getObj);
		ren.fontPath = cfg["font-path"].base;
	}
	if ("font-size" in cfg) {
		if (!isNumber(cfg["font-size"].getObj))
			fail("Invalid digit: " ~ cfg["font-size"].getObj);
		ren.fontSize = to!int(cfg["font-size"].getObj);
	}

	// colours
	theme.background = getTheme(cfg, "background-color", [36, 36, 48]);
	theme.command = getTheme(cfg, "command-color", [102, 102, 102]);
	theme.text = getTheme(cfg, "text-color", [240, 240, 240]);
	theme.key = getTheme(cfg, "key-color", [251, 160, 192]);

	// window title
	ren.windowTitle = "Rennen";
	if ("window-title" in cfg) {
		if (cfg["window-title"].type != ObjType.STRING)
			fail("Invalid string: " ~ cfg["window-title"].getObj);
		ren.windowTitle = cfg["window-title"].base;
	}

	// window size
	if ("window-width" in cfg) {
		if (!isNumber(cfg["window-width"].getObj))
			fail("Invalid digit: " ~ cfg["window-width"].getObj);
		w = to!int(cfg["window-width"].getObj);
	}
	if ("window-height" in cfg) {
		if (!isNumber(cfg["window-height"].getObj))
			fail("Invalid digit: " ~ cfg["window-height"].getObj);
		h = to!int(cfg["window-height"].getObj);
	}

	if (!h)
		h = to!int((cfg["commands"].list.length+1) * (ren.fontSize + ren.spacing));
	ren.windowSize = [w, h];
}

void quit()
{
	SDL_DestroyRenderer(ren.render);
	SDL_DestroyWindow(ren.window);
	TTF_Quit();
	SDL_Quit();
	exit(0);
}

void main(string[] args)
{
	// ROFI CAN SUCK MY DICK-
	if (args.length < 2) {
		writeln("Usage:");
		writeln("  ", args[0], " <path to config file>");
		exit(0);
	}
	
	path = args[1];
	if (path.isDir) {
	path = args[1];
		loadConfigFile(path ~ "/config.sk");
	}
	else {
		loadConfigFile(path);
		// extract whole path except for config file
		path = path.split("/")[0..$-1].join("/");
	}

	// if it can't find then it can't find. ain't gonna look elsewhere >:c
	if (!ren.fontPath.exists)
		ren.fontPath = path ~ "/" ~ ren.fontPath;

	DerelictSDL2.load();
	DerelictSDL2ttf.load();
	SDL_Init(SDL_INIT_EVERYTHING);
	TTF_Init();
	
	// Error handling? What's that?

	ren.window = SDL_CreateWindow(ren.windowTitle.toStringz,
			SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
			ren.windowSize[0], ren.windowSize[1],
			SDL_WINDOW_INPUT_FOCUS | SDL_WINDOW_ALWAYS_ON_TOP);
	ren.render = SDL_CreateRenderer(ren.window, -1, SDL_RENDERER_ACCELERATED);
	ren.font = new Font(ren.fontPath, ren.fontSize);

	while (true) {
		update();
		events();
		SDL_Delay(12);
	}
}
