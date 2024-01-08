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

const int
		RMASK = 0xff000000,
		GMASK = 0x00ff0000,
		BMASK = 0x0000ff00,
		AMASK = 0x000000ff;

struct flags
{
static:
	bool runCommand = true;
}

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

	this(string t_path, int t_size)
	{
		_font = TTF_OpenFont(t_path.toStringz, t_size);
		size = t_size;
		rect = SDL_Rect(0, 0, size, size);
	}

	void write(string text, int[2] pos, SDL_Color col)
	{
		if (text == "") return;
		renderText(text, col);
		rect = SDL_Rect(pos[0], pos[1], _surf.w, _surf.h);
		blitSurface();
	}

	// I forgot to use this function
	void writeCentered(string text, int[2] pos, SDL_Color col)
	{
		if (text == "") return;
		renderText(text, col);
		rect = SDL_Rect(
				pos[0] - (_surf.w/2),
				pos[1] - (_surf.h/2),
				_surf.w,
				_surf.h);
		blitSurface();
	}
	
	void writeRight(string text, int[2] pos, SDL_Color col)
	{
		if (text == "") return;
		renderText(text, col);
		rect = SDL_Rect(
				pos[0] - _surf.w,
				pos[1],
				_surf.w,
				_surf.h);
		blitSurface();
	}

	private void renderText(string text, SDL_Color col)
	{
		_surf = TTF_RenderUTF8_Blended(_font, text.toStringz, col);
	}

	private void blitSurface()
	{
		if (!_surf) return;
		SDL_BlitSurface(_surf, null, ren.surface, &rect);
		SDL_FreeSurface(_surf);
	}
}

struct Cmd {
	string name;
	string cmd;
	int key;
	string key_name;
}

struct theme {
static:
	SDL_Color background;
	SDL_Color command;
	SDL_Color text;
	SDL_Color key;
}

struct ren {
static:
	SDL_Window *window;
	SDL_Renderer *render;
	SDL_Surface *surface;
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
		// ren is actually not supposed to be resizable, but there's always
		// a bitchass window manager to fuck everything up
		case SDL_WINDOWEVENT: {
			if (e.window.event == SDL_WINDOWEVENT_RESIZED) {
				ren.windowSize = [e.window.data1, e.window.data2];
				SDL_FreeSurface(ren.surface);
				ren.surface = SDL_CreateRGBSurface(
						0, ren.windowSize[0], ren.windowSize[1], 32,
						RMASK, GMASK, BMASK, AMASK);
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
				// Don't accept arrow keys when scrolling
				break;
			}

			// cmd keys
			if (ignoredKeys.canFind(key)) break;

			foreach (cmd; ren.cmds) {
				if (key == cmd.key) {
					if (flags.runCommand)
						spawnShell(cmd.cmd ~ " &").wait;
					else
						writeln(cmd.cmd);
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
	SDL_FillRect(ren.surface, null,
			SDL_MapRGBA(ren.surface.format,
				theme.background.r,
				theme.background.g,
				theme.background.b,
				theme.background.a));
	
	for (int i = 0; i < ren.cmds.length; ++i) {
		int y = ren.spacing + (i - ren.scroll) * (ren.font.size + ren.spacing);

		if (y < 0 || y > ren.windowSize[1])
			continue;

		// write key
		ren.font.writeRight(" [" ~ ren.cmds[i].key_name ~ "] ",
				[ren.windowSize[0], y], theme.key);

		// write command
		ren.font.writeRight(ren.cmds[i].cmd,
				[ren.windowSize[0] - ren.font.rect.w, y], theme.command);
	
		// write name
		ren.font.write(" " ~ ren.cmds[i].name, [0, y], theme.text);
	}

	SDL_Texture *texture = SDL_CreateTextureFromSurface(ren.render, ren.surface);
	SDL_RenderCopy(ren.render, texture, null, null);
	SDL_RenderPresent(ren.render);
	SDL_DestroyTexture(texture);
}

ubyte hexToDec(string col)
{
	// bruh.
	ubyte res = 0;
	for (size_t i = 0; i < col.length; ++i) {
		auto j = (col.length-1) - i;
		if (col[j] >= 'A' && col[j] <= 'F') {
			res += (col[j] - 'A' + 10) * (16 ^^ i);
		}
		else if (col[j] >= 'a' && col[j] <= 'f') {
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

SDL_Color getTheme(Obj[string] vars, string key, SDL_Color res)
{
	SDL_Color color;
	if (key in vars) {
		auto col = vars[key];

		if (col.type == ObjType.STRING) {
			if (col.base.length < 6) {
				warn("Invalid color: " ~ col.getObj);
				return res;
			}

			auto offset = (col.base[0] == '#')? 1 : 0;
			color = SDL_Color(
				hexToDec(col.base[0+offset..2+offset]),
				hexToDec(col.base[2+offset..4+offset]),
				hexToDec(col.base[4+offset..6+offset]),
				(col.base.length >= 8?
					hexToDec(col.base[6+offset..8+offset]) : 0xff));
			return color;
		}

		if (col.type != ObjType.LIST || col.list.length < 3) {
			warn("Invalid color: " ~ col.getObj);
			return res;
		}
		
		foreach (i; 0..col.list.length) {
			if (!isNumber(col.list[i].getObj)) {
				warn("Invalid digit: " ~ col.list[i].getObj);
				return res;
			}
		}
		color = SDL_Color(
			to!ubyte(col.list[0].getObj),
			to!ubyte(col.list[1].getObj),
			to!ubyte(col.list[2].getObj),
			(col.list.length == 4? to!ubyte(col.list[3].getObj) : 0xff));
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

		if (![ObjType.INTEGER, ObjType.STRING].canFind(item.list[2].type))
			fail("Invalid key: " ~ item.list[2].getObj);

		int key = (item.list[2].type == ObjType.INTEGER)?
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
	theme.background = getTheme(cfg, "background-color", SDL_Color(36, 36, 48, 255));
	theme.command = getTheme(cfg, "command-color", SDL_Color(102, 102, 102, 255));
	theme.text = getTheme(cfg, "text-color", SDL_Color(240, 240, 240, 255));
	theme.key = getTheme(cfg, "key-color", SDL_Color(251, 160, 192, 255));

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
	SDL_FreeSurface(ren.surface);
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

	string path;
	foreach (arg; args) {
		switch (arg) {
		case "-norun":
			flags.runCommand = false;
			break;
		default:
			path = arg;
			break;
		}
	}
	
	if (path.isDir) {
		path = args[1];
		loadConfigFile(path ~ "/config.sk");
	}
	else {
		loadConfigFile(path);
		// extract whole path except for config file
		path = path.split("/")[0..$-1].join("/");
	}

	// TODO: look for system fonts
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

	ren.surface = SDL_CreateRGBSurface(
			0, ren.windowSize[0], ren.windowSize[1], 32,
			RMASK, GMASK, BMASK, AMASK);

	// Can't quite figure out how to draw transparent background
	// without it affecting the text
	/* SDL_SetWindowOpacity(ren.window, to!float(theme.background.a) / 255); */

	while (true) {
		update();
		events();
		SDL_Delay(12);
	}
}
