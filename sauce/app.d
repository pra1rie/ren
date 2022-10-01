import std.stdio;
import std.string : toStringz;
import std.file : exists, isDir, readText;
import std.array : split;
import std.algorithm : canFind, each;
import std.conv : to;
import std.process : spawnShell, wait;
import core.stdc.stdlib : exit;
import config;

import derelict.sdl2.sdl;
import derelict.sdl2.ttf;

const string CONFIG_PATH = "config";
const string SCANCODES_PATH = "scancodes";
int[string] scancodes;

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
	int fontSize;

	int scroll;
	int spacing;
	int offset;

	bool isScrolling;
	bool isRunning;
	bool exitOnKey;
	Font font;
	Cmd[] cmds;
}

const static size_t FPS = 60;

bool getKey(SDL_Scancode key)
{
	const ubyte *state = SDL_GetKeyboardState(null);
	return state[key]? true : false;
}

void events()
{
	// eventsing
	SDL_Event e;
	if (SDL_PollEvent(&e)) {
		switch (e.type) {
			case SDL_QUIT: {
				ren.isRunning = false;
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

				// scrolling
				if (key == SDL_SCANCODE_LSHIFT)
					ren.isScrolling = true;

				if (ren.isScrolling) {
					if (key == SDL_SCANCODE_DOWN) {
						++ren.scroll;
					}
					if (key == SDL_SCANCODE_UP) {
						--ren.scroll;
						if (ren.scroll <= 0)
							ren.scroll = 0;
					}
				}

				// cmd keys
				if (ignoredKeys.canFind(key)) break;

				foreach (cmd; ren.cmds) {
					if (key == cmd.key) {
						spawnShell(cmd.cmd ~ " &").wait;
						if (!ren.exitOnKey) {
							ren.isRunning = false;
							quit();
						}
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
	if (getKey(SDL_SCANCODE_ESCAPE))
		ren.isRunning = false;

	SDL_SetRenderDrawColor(ren.render,
			theme.background[0], theme.background[1], theme.background[2], 0);
	SDL_RenderClear(ren.render);
	
	// TODO: no need to draw outside screen

	for (int i = 0; i < ren.cmds.length; ++i) {
		// write key
		ren.font.writeRight(" [" ~ ren.cmds[i].key_name ~ "] ",
				[
					ren.windowSize[0],
					ren.offset + (i - ren.scroll) * (ren.font.size + ren.spacing)
				], theme.key);

		// write command
		ren.font.writeRight(ren.cmds[i].cmd,
				[
					ren.windowSize[0] - ren.font.rect.w,
					ren.offset + (i - ren.scroll) * (ren.font.size + ren.spacing)
				], theme.command);
	
		// write name
		ren.font.write(" " ~ ren.cmds[i].name,
				[
					0,
					ren.offset + (i - ren.scroll) * (ren.font.size + ren.spacing)
				], theme.text);
	}

	SDL_RenderPresent(ren.render);
}

ubyte[3] getTheme(Obj[string] vars, string key, ubyte[3] res)
{
	ubyte[3] color;

	// TODO: maybe support colours in hex as well
	if (key in vars) {
		auto col = vars[key];
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

void loadConfigFile(string path, string scancodesPath)
{
	auto scum = loadConfig(scancodesPath);
	foreach (var; scum.vars.byKeyValue) {
		if (var.value.type == ObjType.INTEGER)
			scancodes[var.key] = to!int(var.value.getObj);
	}

	auto cfg = loadConfig(path);
	if (!("commands" in cfg.vars))
		fail("Variable does not exist: commands");
	if (cfg.vars["commands"].type != ObjType.LIST)
		fail("Variable must be a list");

	foreach (item; cfg.vars["commands"].list) {
		if (item.list.length != 3)
			fail("Invalid command: " ~ item.getObj);

		if (!isNumber(item.list[2].base) && !(item.list[2].base in scancodes))
			fail("Invalid key: " ~ item.list[2].base);

		int key = (item.list[2].base.isNumber)?
				to!int(item.list[2].base) : scancodes[item.list[2].base];

		ren.cmds ~= Cmd(item.list[0].base, item.list[1].base, key, item.list[2].base);
	}

	// text positioning
	ren.scroll = 0;
	ren.spacing = 3;
	ren.offset = 12;

	if ("spacing" in cfg.vars) {
		if (!isNumber(cfg.vars["spacing"].getObj))
			fail("Invalid digit: " ~ cfg.vars["spacing"].getObj);

		ren.spacing = to!int(cfg.vars["spacing"].getObj);
	}
	if ("offset" in cfg.vars) {
		if (!isNumber(cfg.vars["offset"].getObj))
			fail("Invalid digit: " ~ cfg.vars["offset"].getObj);

		ren.offset = to!int(cfg.vars["offset"].getObj);
	}

	int w = 640, h = 0;
	ren.fontSize = 0;

	// font
	if ("font-size" in cfg.vars) {
		if (!isNumber(cfg.vars["font-size"].getObj))
			fail("Invalid digit: " ~ cfg.vars["font-size"].getObj);

		ren.fontSize = to!int(cfg.vars["font-size"].getObj);
	}

	// colours
	theme.background = getTheme(cfg.vars, "background-color", [36, 36, 48]);
	theme.command = getTheme(cfg.vars, "command-color", [102, 102, 102]);
	theme.text = getTheme(cfg.vars, "text-color", [240, 240, 240]);
	theme.key = getTheme(cfg.vars, "key-color", [251, 160, 192]);

	// window size
	if ("window-width" in cfg.vars) {
		if (!isNumber(cfg.vars["window-width"].getObj))
			fail("Invalid digit: " ~ cfg.vars["window-width"].getObj);

		w = to!int(cfg.vars["window-width"].getObj);
	}
	if ("window-height" in cfg.vars) {
		if (!isNumber(cfg.vars["window-height"].getObj))
			fail("Invalid digit: " ~ cfg.vars["window-height"].getObj);

		h = to!int(cfg.vars["window-height"].getObj);
	}

	if (!h)
		h = to!int(ren.fontSize * (cfg.vars["commands"].list.length-1 + ren.spacing));
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
	if (args.length < 2) {
		writeln("Usage:");
		writeln("  ", args[0], " <flags> <path to config files>");
		writeln("flags:");
		writeln("  -q closes program after a key is pressed");
		exit(0);
	}
	
	string path;
	foreach (arg; args[1..$]) {
		if (arg.length == 0) continue;
		if (arg[0] == '-') {
			if (arg == "-q")
				ren.exitOnKey = true;
		}
		else {
			path = arg;
		}
	}

	loadConfigFile(path ~ "/" ~ CONFIG_PATH, path ~ "/" ~ SCANCODES_PATH);

	DerelictSDL2.load();
	DerelictSDL2ttf.load();
	SDL_Init(SDL_INIT_EVERYTHING);
	TTF_Init();
	
	// Error handling? What's that?

	ren.window = SDL_CreateWindow("Rennen",
			SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
			ren.windowSize[0], ren.windowSize[1], SDL_WINDOW_RESIZABLE);
	ren.render = SDL_CreateRenderer(ren.window, -1, SDL_RENDERER_ACCELERATED);
	ren.isRunning = true;
	ren.font = new Font(path ~ "/font.ttf", ren.fontSize);

	while (ren.isRunning) {
		events();
		update();
		SDL_Delay(1000 / FPS);
	}

	quit();
}
