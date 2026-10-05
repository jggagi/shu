# Provider policy

| Request | Backend |
| --- | --- |
| Small set of scene / character / style references to establish art direction | Codex built-in image generation when available |
| Production assets / bulk / candidates / variants / explicit Qwen | `qwen-image-3.0`, using selected references |
| Explicit Codex image generation / precise edit request | Codex built-in image generation when available |
| Explicit Qwen Pro request | `qwen-image-3.0-pro` |
| Codex built-in unavailable | `qwen-image-3.0`, with the backend switch stated |

Never silently use the paid OpenAI Image API. Built-in imagegen is an agent tool, not an HTTP client route.

## Reference-to-production handoff

Use this division as the default for reducing batch production cost, while preserving explicit user backend choices:

1. Reuse selected project references, or create only the missing scene, character or style references with Codex. Save the exact prompts and provenance in the configured project locations.
2. For Qwen production, pass the actual selected images with `--reference`; a written style description alone is not the reference handoff. Choose the relevant composition, identity and style references within the CLI's supported limit. Keep the shared visual constraints stable and vary only the requested asset or pose.
3. Generate a small sample within the authorized production scope. Inspect framing, style, character identity, legibility and actual alpha when needed before expanding the same recipe into a batch. If it fails, revise the prompt or references before producing more assets.
4. Produce the requested batch with `qwen-image-3.0` through the repo CLI. Each output records its exact prompt, backend/model, references and SHA256; review and select assets before project integration. Codex generating a reference does not make the resulting Qwen assets automatically approved.

Updating this workflow does not itself authorize billable generations. A production request authorizes its scoped sample and batch; offline skill validation does not. Preserve the no-automatic-retry rule for failed or uncertain billable calls.

## Qwen wire contract

Verified 2026-10-04 against [Alibaba Cloud Model Studio's API reference](https://www.alibabacloud.com/help/en/model-studio/qwen-image-generation-and-editing-api-reference) (updated 2026-10-03): synchronous JSON POST to the complete endpoint from `QWEN_IMAGE_ENDPOINT`, `Authorization: Bearer` using `DASHSCOPE_API_KEY`. All fields are top-level. T2I sends `model`, `prompt`; this CLI fixes `n=1`, defaults `prompt_extend=true`, `watermark=false`. Optional documented fields: `size`, `negative_prompt`, `seed`. No automatic Pro selection or hardcoded endpoint/region.

I2I/editing uses `image` (one string or an ordered array), not `images`, multipart `/images/edits`, or masks. Qwen 3.0 accepts 1–3 images: PNG/JPEG/BMP/TIFF/WebP/GIF, at most 10 MB each; recommended dimensions 384–2048. Local files are `data:{MIME_type};base64,{data}`; HTTPS references are passed directly to the selected provider, not fetched locally. Remote image size/dimensions are validated by the provider.

`size` is `auto` or `WIDTHxHEIGHT`, area 512²–2048² pixels, aspect ratio 1:8–8:1. Omission uses provider sizing. Seed range: 0–2147483647. Response: `data[0].url`, PNG download; links expire after 24 hours. `response_format=b64_json` is ignored, so the CLI uses URL downloads. Timeout is 600 seconds, with no automatic retry. API and download redirects are refused to prevent unapproved forwarding; downloads receive no Authorization header. Failures redact raw provider messages and URLs.

`enable_thinking` defaults to true and requires `prompt_extend=true`. Accordingly, `--no-prompt-extend` also sends `enable_thinking=false`. Negative prompts are saved separately under the prompt directory and referenced by `negative_prompt_file` in provenance.

Neither doctor nor tests perform billable calls. Local readiness does not prove region access, credits, network connectivity, or output quality. Built-in output uses provider `codex-imagegen`, model `null`. New JSONL records include exact prompt-file path, repo-relative output/reference paths, UTC time and SHA256. No parallel manifest writers.
