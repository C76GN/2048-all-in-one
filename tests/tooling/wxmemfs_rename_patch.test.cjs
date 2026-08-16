"use strict";

const assert = require("node:assert/strict");
const childProcess = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const projectRoot = path.resolve(__dirname, "../..");
const patchScriptPath = path.join(
	projectRoot,
	"tools/wechat_minigame/wxmemfs_rename_patch.ps1",
);

const BROKEN_RENAME_SOURCE = [
	"const nodeOps={",
	"rename:function(old_node,new_dir,new_name){",
	"var existing;",
	"try{existing=FS[\"lookupNode\"](new_dir,new_name)}catch(e){}",
	"if(existing){if(FS[\"isDir\"](old_node[\"mode\"])){",
	"throw new FS[\"ErrnoError\"](39)}FS[\"hashRemoveNode\"](existing)}",
	"delete old_node[\"parent\"][\"contents\"][old_node[\"name\"]];",
	"new_dir[\"contents\"][new_name]=old_node;",
	"old_node[\"name\"]=new_name;old_node[\"parent\"]=new_dir;",
	"new_dir[\"ctime\"]=new_dir[\"mtime\"]=old_node[\"parent\"][\"ctime\"]",
	"=old_node[\"parent\"][\"mtime\"]=Date[\"now\"]();",
	"if(WXMEMFS[\"wxBasePath\"]){var oldWxPath=WXMEMFS[\"getWxPath\"](",
	"FS[\"getPath\"](old_node[\"parent\"])+\"/\"+old_node[\"name\"]);",
	"var newWxPath=WXMEMFS[\"getWxPath\"](",
	"FS[\"getPath\"](new_dir)+\"/\"+new_name);",
	"try{wx[\"getFileSystemManager\"]()[\"renameSync\"](oldWxPath,newWxPath)}",
	"catch(e){WXMEMFS[\"logError\"](e[\"message\"])}}},",
	"unlink:function(){}",
	"};",
].join("");

function quotePowerShellLiteral(value) {
	return `'${value.replaceAll("'", "''")}'`;
}

function applyPatch(source) {
	const temporaryRoot = fs.mkdtempSync(path.join(os.tmpdir(), "wxmemfs-patch-"));
	const inputPath = path.join(temporaryRoot, "input.js");
	const outputPath = path.join(temporaryRoot, "output.js");
	try {
		fs.writeFileSync(inputPath, source, "utf8");
		const command = [
			"$ErrorActionPreference = 'Stop'",
			`. ${quotePowerShellLiteral(patchScriptPath)}`,
			`$source = [IO.File]::ReadAllText(${quotePowerShellLiteral(inputPath)}, [Text.UTF8Encoding]::new($false))`,
			"$patched = ConvertTo-WeChatWxMemFsRenamePatchedSource -Source $source",
			`[IO.File]::WriteAllText(${quotePowerShellLiteral(outputPath)}, $patched, [Text.UTF8Encoding]::new($false))`,
		].join("\n");
		const result = childProcess.spawnSync(
			"powershell.exe",
			["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", command],
			{encoding: "utf8"},
		);
		assert.equal(result.status, 0, result.stderr || result.stdout);
		return fs.readFileSync(outputPath, "utf8");
	} finally {
		fs.rmSync(temporaryRoot, {recursive: true, force: true});
	}
}

function extractRenameFunction(source, sandbox) {
	const prefix = "rename:";
	const start = source.indexOf(prefix);
	const end = source.indexOf(",unlink:function", start + prefix.length);
	assert.notEqual(start, -1);
	assert.notEqual(end, -1);
	const expression = source.slice(start + prefix.length, end);
	return vm.runInNewContext(`(${expression})`, sandbox);
}

test("patch preserves the physical source path before mutating the MEMFS node", () => {
	const patchedSource = applyPatch(BROKEN_RENAME_SOURCE);
	const renameCalls = [];
	const directory = {contents: {}, ctime: 0, mtime: 0};
	const pendingName = "layout.json.pending-00000000-0000-4000-8000-000000000000";
	const oldNode = {
		parent: directory,
		name: pendingName,
		mode: 0,
		ctime: 0,
		mtime: 0,
	};
	directory.contents[pendingName] = oldNode;

	const sandbox = {
		FS: {
			lookupNode() {
				throw new Error("destination absent");
			},
			isDir() {
				return false;
			},
			hashRemoveNode() {},
			getPath(node) {
				assert.equal(node, directory);
				return "/userfs/saves/.gf-storage/v1";
			},
			ErrnoError: Error,
		},
		WXMEMFS: {
			wxBasePath: true,
			getWxPath(value) {
				return `/physical${value}`;
			},
			log() {},
			logError(message) {
				throw new Error(message);
			},
		},
		wx: {
			getFileSystemManager() {
				return {
					renameSync(oldPath, newPath) {
						renameCalls.push([oldPath, newPath]);
					},
				};
			},
		},
	};
	const rename = extractRenameFunction(patchedSource, sandbox);
	rename(oldNode, directory, "layout.json");

	assert.deepEqual(renameCalls, [[
		`/physical/userfs/saves/.gf-storage/v1/${pendingName}`,
		"/physical/userfs/saves/.gf-storage/v1/layout.json",
	]]);
	assert.equal(directory.contents[pendingName], undefined);
	assert.equal(directory.contents["layout.json"], oldNode);
});

test("physical rename failure leaves the in-memory source node unchanged", () => {
	const patchedSource = applyPatch(BROKEN_RENAME_SOURCE);
	const logErrors = [];
	const directory = {contents: {}, ctime: 0, mtime: 0};
	const pendingName = "layout.json.pending-00000000-0000-4000-8000-000000000000";
	const oldNode = {
		parent: directory,
		name: pendingName,
		mode: 0,
		ctime: 0,
		mtime: 0,
	};
	directory.contents[pendingName] = oldNode;
	class ErrnoError extends Error {
		constructor(errno) {
			super(`errno:${errno}`);
			this.errno = errno;
		}
	}

	const sandbox = {
		FS: {
			lookupNode() {
				throw new Error("destination absent");
			},
			isDir() {
				return false;
			},
			hashRemoveNode() {},
			getPath(node) {
				assert.equal(node, directory);
				return "/userfs/saves/.gf-storage/v1";
			},
			ErrnoError,
		},
		WXMEMFS: {
			wxBasePath: true,
			getWxPath(value) {
				return `/physical${value}`;
			},
			log() {},
			logError(...values) {
				logErrors.push(values);
			},
		},
		wx: {
			getFileSystemManager() {
				return {
					renameSync() {
						throw new Error("physical failure");
					},
				};
			},
		},
	};
	const rename = extractRenameFunction(patchedSource, sandbox);
	assert.throws(
		() => rename(oldNode, directory, "layout.json"),
		(error) => error instanceof ErrnoError && error.errno === 29,
	);

	assert.equal(oldNode.name, pendingName);
	assert.equal(oldNode.parent, directory);
	assert.equal(directory.contents[pendingName], oldNode);
	assert.equal(directory.contents["layout.json"], undefined);
	assert.equal(logErrors.length, 1);
});
