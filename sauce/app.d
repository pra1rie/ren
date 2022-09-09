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

static struct ren {
static:
	SDL_Window *window;
	SDL_Renderer *render;
	int[2] windowSize;
	int fontSize;
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
			case SDL_KEYDOWN: {
				auto key = e.key.keysym.scancode;
				if (ignoredKeys.canFind(key)) break;
				foreach (cmd; ren.cmds) {
					if (key == cmd.key) {
						spawnShell(cmd.cmd ~ " &").wait;
						if (ren.exitOnKey) {
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

const int pos = 12;
const int space = 3;

void update()
{
	if (getKey(SDL_SCANCODE_ESCAPE))
		ren.isRunning = false;

	SDL_SetRenderDrawColor(ren.render, 36, 36, 48, 0);
	SDL_RenderClear(ren.render);

	for (int i = 0; i < ren.cmds.length; ++i) {
		// write key
		ren.font.writeRight(" [" ~ ren.cmds[i].key_name ~ "] ",
				[ren.windowSize[0], pos + i * (ren.font.size + space)],
				[251, 160, 192]);

		// write command
		ren.font.writeRight(ren.cmds[i].cmd,
				[ren.windowSize[0] - ren.font.rect.w, pos + i * (ren.font.size + space)],
				[102, 102, 102]);
	
		// write name
		ren.font.write(" " ~ ren.cmds[i].name,
				[0, pos + i * (ren.font.size + space)],
				[240, 240, 240]);
	}

	SDL_RenderPresent(ren.render);
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

		if (!isNumber(item.list[2].base) && !(item.list[2].base in scancodes)) {
			fail("Invalid key: " ~ item.list[2].base);
			continue;
		}

		int key = (item.list[2].base.isNumber)?
				to!int(item.list[2].base) : scancodes[item.list[2].base];

		ren.cmds ~= Cmd(
					item.list[0].base, item.list[1].base, key, item.list[2].base);
	}

	int w = 640, h = 0;
	ren.fontSize = 0;

	if ("font-size" in cfg.vars) {
		if (!isNumber(cfg.vars["font-size"].getObj))
			fail("Invalid digit: " ~ cfg.vars["font-size"].getObj);

		ren.fontSize = to!int(cfg.vars["font-size"].getObj);
	}

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

	if (!h) {
		h = to!int(ren.fontSize * (cfg.vars["commands"].list.length + space));
	}

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
