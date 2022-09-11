module config;
import std.stdio : stderr, writeln;
import std.algorithm : each, canFind;
import std.array : split;
import std.conv : to;
import std.file : exists, isDir, readText;
import core.stdc.stdlib : exit;


bool isNumber(string str) {
	if (str == "") return false;
	string digits = "0123456789";
	foreach (n; str) {
		if (!digits.canFind(n))
			return false;
	}
	return true;
}

void fail(string err) {
	stderr.writeln("[ERROR] " ~ err);
	exit(1);
}

void warn(string err) {
	stderr.writeln("[WARN] " ~ err);
}

enum ObjType {
	NIL,
	STRING,
	INTEGER,
	LIST,
}

struct Obj {
	ObjType type;
	string base;
	Obj[] list;

	this(int value) {
		type = ObjType.INTEGER;
		base = to!string(value);
	}

	this(string value) {
		type = (value == "")? ObjType.NIL : ObjType.STRING;
		base = value;
	}

	this(Obj[] value) {
		type = ObjType.LIST;
		list = value;
	}
}

struct Config {
	Obj[string] vars;
	string[] toks;
	size_t pos = 0;

	void execute() {
		while (pos < toks.length) {
			parseExpr();
		}
	}

private:
	Obj parseExpr() {
		if (toks[pos].isNumber())
			return parseNumber();

		switch (toks[pos][0]) {
			case '\"':
				return parseString();
			case '[':
				return parseList();
			case ']':
			case ':':
			case ',':
				fail("Unexpected token: " ~ toks[pos]);
				return Obj("");
			default:
				return parseName();
		}
	}
	
	Obj parseNumber() {
		auto num = toks[pos++];
		return Obj(to!int(num));
	}

	Obj parseString() {
		auto str = toks[pos++][1..$-1];
		return Obj(str);
	}

	Obj parseList() {
		Obj[] list;
		++pos; // [
		list ~= parseExpr();

		while (pos < toks.length && toks[pos] == ",") {
			++pos;
			if (toks[pos] == "]") break;
			list ~= parseExpr();
		}
		if (toks[pos] != "]")
			fail("Unexpected token " ~ toks[pos]);
		++pos; // ]
		return Obj(list);
	}

	Obj parseName() {
		auto name = toks[pos++];
		if (toks[pos] == ":") {
			++pos;
			auto expr = parseExpr();
			vars[name] = expr;
			return expr;
		}

		if (!(name in vars))
			fail("Variable does not exist: " ~ name);
		return vars[name];
	}
}

string[] parse(string file) {
	string ignored = "\t\r\n;";
	string separators = ",:[]\"";
	string[] toks;
	string text;

	bool isString, isComment;
	string toString;

	foreach (letter; file) {
		if (letter == '#' && !isString) {
			isComment = !isComment;
			continue;
		}
		if (isComment) continue;

		if (letter == '\"' && !isComment)
			isString = !isString;

		if (isString && letter == ' ') text ~= " \rspace\r ";
		if ((ignored ~ separators).canFind(letter))
			text ~= " " ~ letter ~ " ";
		else
			text ~= letter;
	}

	isString = false;
	toString = "";

	foreach (word; text.split(" ")) {
		if (word == "\"") {
			isString = !isString;
			if (!isString) {
				toks ~= "\"" ~ toString ~ "\"";
				toString = "";
			}
			continue;
		}
		if (isString) {
			if (word == "\rspace\r")
				toString ~= " ";
			else
				toString ~= word;
			continue;
		}

		if (word == "" || ignored.canFind(word)) continue;
		toks ~= word;
	}

	return toks;
}

string getObj(Obj obj) {
	if (obj.type == ObjType.NIL)
		return "nil";
	if (obj.type == ObjType.STRING)
		return "\"" ~ obj.base ~ "\"";
	if (obj.type == ObjType.INTEGER)
		return obj.base;
	
	string s = "[";
	foreach (o; obj.list)
		s ~= o.getObj ~ ", ";
	return s[0..$-2] ~ "]";
}

Config loadConfig(string path) {
	if (!path.exists || path.isDir)
		fail("Could not open file: " ~ path);
	Config cfg;
	cfg.toks = parse(readText(path));
	cfg.execute();
	return cfg;
}

