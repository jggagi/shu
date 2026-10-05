# Prompt contract

```text
Asset type:
Purpose:
Primary request:
Reference images:
Scene/backdrop:
Subject:
Style/medium:
Composition/framing:
Lighting/mood:
Color palette:
Materials/textures:
Constraints:
Avoid:
```

Preserve user art direction; do not add unnecessary story/worldbuilding. Specify edit invariants as `change X; preserve Y and Z`. Identify edit targets separately from style/composition/identity references and preserve their supplied order.

Scene references should establish reusable visual language and readable spatial layers. Use reproducible descriptions of brushwork, line weight, palette and materials instead of vague adjectives. Avoid text, logos, watermarks, signatures, borders and fake UI unless requested. Describe desired transparency when needed, but verify actual alpha after generation.

Read the target game's current spec and selected references from the configured reference directory instead of inventing a new style. Chinese ink/watercolor/gongbi, restrained blue-green accents and layered composition are one project's example, not a required style for every game. Save exact production prompts under the configured prompt directory; provenance points to the file rather than duplicating prompt text into logs.
