import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const PROVIDER_ID = process.env.PI_LOCAL_QWEN_AMD_PROVIDER_ID ?? "local-qwen-amd";
const HOST = process.env.PI_LOCAL_QWEN_AMD_HOST ?? "127.0.0.1";
const PORT = process.env.PI_LOCAL_QWEN_AMD_PORT ?? "8004";
const BASE_URL = `http://${HOST}:${PORT}/v1`;
const PACKAGE_DIR = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const SERVER_SCRIPT = process.env.PI_LOCAL_QWEN_AMD_SERVER_SCRIPT ?? resolve(PACKAGE_DIR, "scripts/server.sh");
const INSTALL_SCRIPT = process.env.PI_LOCAL_QWEN_AMD_INSTALL_SCRIPT ?? resolve(PACKAGE_DIR, "scripts/install.sh");

const models = [
	{
		id: "qwen35-9b-mtp-fast",
		name: "Qwen3.5 9B MTP Q4 Fast (local AMD llama.cpp)",
		contextWindow: Number(process.env.PI_LOCAL_QWEN_AMD_QWEN_CTX_SIZE ?? "65536"),
		maxTokens: 8192,
	},
	{
		id: "qwopus35-9b-coder-mtp-q5-100k",
		name: "Qwopus3.5 9B Coder MTP Q5 100K (local AMD llama.cpp)",
		contextWindow: Number(process.env.PI_LOCAL_QWEN_AMD_QWOPUS_CTX_SIZE ?? "100000"),
		maxTokens: 8192,
	},
];
const modelIds = new Set(models.map((model) => model.id));

function managedModelId(model: { provider?: string; id?: string } | undefined): string | undefined {
	if (model?.provider !== PROVIDER_ID) return undefined;
	if (!model.id || !modelIds.has(model.id)) return undefined;
	return model.id;
}

export default function (pi: ExtensionAPI) {
	let selectedModel: string | undefined;
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
		models: models.map((model) => ({
			id: model.id,
			name: model.name,
			reasoning: true,
			input: ["text"],
			contextWindow: model.contextWindow,
			maxTokens: model.maxTokens,
			cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
		})),
	});

	function enqueue(task: () => Promise<void>): Promise<void> {
		queue = queue.then(task, task);
		return queue;
	}

	async function run(args: string[], timeout: number): Promise<string> {
		const result = await pi.exec(SERVER_SCRIPT, args, { timeout });
		const output = [result.stdout, result.stderr].filter(Boolean).join("\n").trim();
		if (result.code !== 0) throw new Error(output || `${SERVER_SCRIPT} ${args.join(" ")} exited with ${result.code}`);
		return output;
	}

	async function start(ctx: any, modelId: string, reason: string): Promise<void> {
		if (selectedModel === modelId) return;
		if (selectedModel && selectedModel !== modelId) await stop(ctx, "model_change");
		selectedModel = modelId;
		if (ctx.hasUI) ctx.ui.setStatus("local-qwen", `${modelId} starting…`);
		try {
			const output = await run(["start", modelId], 180_000);
			if (ctx.hasUI) {
				ctx.ui.setStatus("local-qwen", `${modelId} 🟢`);
				ctx.ui.notify(`Started ${PROVIDER_ID}/${modelId} at ${BASE_URL}`, "info");
			}
			console.log(`[pi-local-qwen-amd] start ${modelId} (${reason}): ${output}`);
		} catch (error) {
			selectedModel = undefined;
			if (ctx.hasUI) {
				ctx.ui.setStatus("local-qwen", `${modelId} failed`);
				ctx.ui.notify(`Failed to start ${modelId}. Run installer: ${INSTALL_SCRIPT} --model ${modelId}`, "error");
			}
			throw error;
		}
	}

	async function stop(ctx: any, reason: string): Promise<void> {
		if (!selectedModel) return;
		const stopped = selectedModel;
		selectedModel = undefined;
		if (process.env.PI_LOCAL_QWEN_AMD_KEEP_SERVER === "1") {
			if (ctx.hasUI) ctx.ui.setStatus("local-qwen", `${stopped} kept`);
			console.log(`[pi-local-qwen-amd] keep server on ${reason}`);
			return;
		}
		const output = await run(["stop"], 30_000);
		if (ctx.hasUI) {
			ctx.ui.setStatus("local-qwen", undefined);
			if (reason !== "shutdown") ctx.ui.notify(`Stopped ${stopped}`, "info");
		}
		console.log(`[pi-local-qwen-amd] stop ${stopped} (${reason}): ${output}`);
	}

	pi.on("model_select", async (event, ctx) => {
		const next = managedModelId(event.model);
		const prev = managedModelId(event.previousModel);
		if (next) await enqueue(() => start(ctx, next, `model_select:${event.source}`));
		else if (prev) await enqueue(() => stop(ctx, "model_change"));
	});

	pi.on("session_start", async (_event, ctx) => {
		const current = managedModelId(ctx.model);
		if (current) await enqueue(() => start(ctx, current, "session_start"));
	});

	pi.on("before_provider_request", async (_event, ctx) => {
		const current = managedModelId(ctx.model);
		if (current) await enqueue(() => start(ctx, current, "before_provider_request"));
	});

	pi.on("session_shutdown", async (_event, ctx) => {
		await enqueue(() => stop(ctx, "shutdown"));
	});

	pi.registerCommand("local-qwen-amd", {
		description: "Manage the local Qwen AMD llama.cpp server: start <model>, stop, status, install",
		handler: async (args, ctx) => {
			const parts = ((args ?? "").trim() || "status").split(/\s+/);
			const command = parts[0];
			if (command === "install") {
				ctx.ui.notify(`Run in a terminal: ${INSTALL_SCRIPT} --model ${parts[1] ?? "qwopus"}`, "info");
				return;
			}
			if (!["start", "stop", "status", "profiles"].includes(command)) {
				ctx.ui.notify("Usage: /local-qwen-amd [start <qwen|qwopus>|stop|status|profiles|install]", "error");
				return;
			}
			const output = await run(parts, command === "start" ? 180_000 : 30_000);
			ctx.ui.notify(output || `${command} completed`, "info");
		},
	});
}
