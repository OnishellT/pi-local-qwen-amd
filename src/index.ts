import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const PROVIDER_ID = process.env.PI_LOCAL_QWEN_AMD_PROVIDER_ID ?? "local-qwen-amd";
const MODEL_ID = process.env.PI_LOCAL_QWEN_AMD_MODEL_ID ?? "qwen35-9b-mtp-fast";
const MODEL_NAME = process.env.PI_LOCAL_QWEN_AMD_MODEL_NAME ?? "Qwen3.5 9B MTP Fast (local AMD llama.cpp)";
const HOST = process.env.PI_LOCAL_QWEN_AMD_HOST ?? "127.0.0.1";
const PORT = process.env.PI_LOCAL_QWEN_AMD_PORT ?? "8004";
const CONTEXT_WINDOW = Number(process.env.PI_LOCAL_QWEN_AMD_CTX_SIZE ?? "65536");
const MAX_TOKENS = Number(process.env.PI_LOCAL_QWEN_AMD_MAX_TOKENS ?? "8192");
const BASE_URL = `http://${HOST}:${PORT}/v1`;
const PACKAGE_DIR = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const SERVER_SCRIPT = process.env.PI_LOCAL_QWEN_AMD_SERVER_SCRIPT ?? resolve(PACKAGE_DIR, "scripts/server.sh");
const INSTALL_SCRIPT = process.env.PI_LOCAL_QWEN_AMD_INSTALL_SCRIPT ?? resolve(PACKAGE_DIR, "scripts/install.sh");

function isManagedModel(model: { provider?: string; id?: string } | undefined): boolean {
	return model?.provider === PROVIDER_ID && model?.id === MODEL_ID;
}

export default function (pi: ExtensionAPI) {
	let selected = false;
	let queue: Promise<void> = Promise.resolve();

	pi.registerProvider(PROVIDER_ID, {
		name: "Local Qwen AMD llama.cpp",
		baseUrl: BASE_URL,
		apiKey: "sk-local-no-key-required",
		api: "openai-completions",
		compat: {
			supportsStore: false,
			supportsDeveloperRole: false,
			supportsReasoningEffort: false,
			supportsUsageInStreaming: false,
			maxTokensField: "max_tokens",
			thinkingFormat: "qwen-chat-template",
		},
		models: [
			{
				id: MODEL_ID,
				name: MODEL_NAME,
				reasoning: true,
				input: ["text"],
				contextWindow: CONTEXT_WINDOW,
				maxTokens: MAX_TOKENS,
				cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
			},
		],
	});

	function enqueue(task: () => Promise<void>): Promise<void> {
		queue = queue.then(task, task);
		return queue;
	}

	async function run(command: "start" | "stop" | "status", timeout: number): Promise<string> {
		const result = await pi.exec(SERVER_SCRIPT, [command], { timeout });
		const output = [result.stdout, result.stderr].filter(Boolean).join("\n").trim();
		if (result.code !== 0) {
			throw new Error(output || `${SERVER_SCRIPT} ${command} exited with ${result.code}`);
		}
		return output;
	}

	async function start(ctx: any, reason: string): Promise<void> {
		if (selected) return;
		selected = true;
		if (ctx.hasUI) ctx.ui.setStatus("local-qwen", "Qwen AMD starting…");
		try {
			const output = await run("start", 180_000);
			if (ctx.hasUI) {
				ctx.ui.setStatus("local-qwen", "Qwen AMD 🟢");
				ctx.ui.notify(`Started ${MODEL_NAME} at ${BASE_URL}`, "info");
			}
			console.log(`[pi-local-qwen-amd] start (${reason}): ${output}`);
		} catch (error) {
			selected = false;
			if (ctx.hasUI) {
				ctx.ui.setStatus("local-qwen", "Qwen AMD failed");
				ctx.ui.notify(`Failed to start ${MODEL_NAME}. Run installer: ${INSTALL_SCRIPT}`, "error");
			}
			throw error;
		}
	}

	async function stop(ctx: any, reason: string): Promise<void> {
		if (!selected) return;
		selected = false;
		if (process.env.PI_LOCAL_QWEN_AMD_KEEP_SERVER === "1") {
			if (ctx.hasUI) ctx.ui.setStatus("local-qwen", "Qwen AMD kept");
			console.log(`[pi-local-qwen-amd] keep server on ${reason}`);
			return;
		}
		const output = await run("stop", 30_000);
		if (ctx.hasUI) {
			ctx.ui.setStatus("local-qwen", undefined);
			if (reason !== "shutdown") ctx.ui.notify(`Stopped ${MODEL_NAME}`, "info");
		}
		console.log(`[pi-local-qwen-amd] stop (${reason}): ${output}`);
	}

	pi.on("model_select", async (event, ctx) => {
		const next = isManagedModel(event.model);
		const prev = isManagedModel(event.previousModel);
		if (next) await enqueue(() => start(ctx, `model_select:${event.source}`));
		else if (prev) await enqueue(() => stop(ctx, "model_change"));
	});

	pi.on("session_start", async (_event, ctx) => {
		if (isManagedModel(ctx.model)) await enqueue(() => start(ctx, "session_start"));
	});

	pi.on("before_provider_request", async (_event, ctx) => {
		if (isManagedModel(ctx.model)) await enqueue(() => start(ctx, "before_provider_request"));
	});

	pi.on("session_shutdown", async (_event, ctx) => {
		await enqueue(() => stop(ctx, "shutdown"));
	});

	pi.registerCommand("local-qwen-amd", {
		description: "Manage the local Qwen AMD llama.cpp server: start, stop, status, install",
		handler: async (args, ctx) => {
			const command = ((args ?? "").trim() || "status").split(/\s+/)[0];
			if (command === "install") {
				ctx.ui.notify(`Run this installer in a terminal: ${INSTALL_SCRIPT}`, "info");
				return;
			}
			if (!["start", "stop", "status"].includes(command)) {
				ctx.ui.notify("Usage: /local-qwen-amd [start|stop|status|install]", "error");
				return;
			}
			const output = await run(command as "start" | "stop" | "status", command === "start" ? 180_000 : 30_000);
			ctx.ui.notify(output || `${command} completed`, "info");
		},
	});
}
