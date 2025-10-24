#!/usr/bin/env bash
set -euo pipefail

# =========[ CONFIG ]=========
APP_NAME=${1:-my-app}

# =========[ ASCII BANNER ]=========
cat <<'BANNER'
───────────────────────────────────────────────
   _____ _            _                _     
  / ____| |          | |              | |    
 | (___ | | ___   ___| | _____ _ __ __| |___ 
  \___ \| |/ _ \ / __| |/ / _ \ '__/ _` / __|
  ____) | | (_) | (__|   <  __/ | | (_| \__ \
 |_____/|_|\___/ \___|_|\_\___|_|  \__,_|___/
───────────────────────────────────────────────
     React + Bun + Tailwind + shadcn/ui
───────────────────────────────────────────────
BANNER

# =========[ PRECHECKS ]=========
need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1" >&2; exit 1; }; }
need_cmd git
need_cmd bun

if [ -e "$APP_NAME" ]; then
  echo "Target path '$APP_NAME' already exists. Choose a different name or remove it." >&2
  exit 1
fi

# =========[ STEP 1: BASE PROJECT ]=========
echo "Creating Vite + React + TypeScript project..."
TMP_DIR="$(mktemp -d)"
git clone --depth 1 https://github.com/vitejs/vite.git "$TMP_DIR" >/dev/null
cp -R "$TMP_DIR/packages/create-vite/template-react-ts" "$APP_NAME"
rm -rf "$TMP_DIR"
cd "$APP_NAME"

# Set package name
if command -v jq >/dev/null 2>&1; then
  tmp=$(mktemp)
  jq --arg name "$APP_NAME" '.name=$name' package.json > "$tmp" && mv "$tmp" package.json
else
  sed -i 's/"name": *"[^"]*"/"name": "'"$APP_NAME"'"/' package.json || true
fi

echo "Installing dependencies..."
bun install

# =========[ STEP 2: TAILWIND + CORE DEPS ]=========
echo "Setting up Tailwind CSS and core deps..."
bun add -d tailwindcss postcss autoprefixer
bun add react-router-dom class-variance-authority tailwind-merge lucide-react

mkdir -p src
# default stylesheet (will be overwritten for v4 below)
cat > src/index.css <<'EOF'
@tailwind base;
@tailwind components;
@tailwind utilities;
EOF

# ensure stylesheet is imported
if ! grep -q "import './index.css'" src/main.tsx 2>/dev/null; then
  sed -i "1i import './index.css'" src/main.tsx
fi

# Tailwind v3/v4 handling
if [ -x node_modules/.bin/tailwindcss ]; then
  echo "Detected Tailwind CLI (v3.x)"
  [ -f postcss.config.js ] || cat > postcss.config.js <<'EOF'
export default {
  plugins: {
    tailwindcss: {},
    autoprefixer: {},
  },
}
EOF
  [ -f tailwind.config.js ] || bunx tailwindcss init -p
  sed -i 's/content: \[\]/content: \[".\/index.html", ".\/src\/**\/*.{js,ts,jsx,tsx}"\],/' tailwind.config.js || true
else
  echo "Tailwind v4 detected — configuring PostCSS and entry CSS..."
  cat > postcss.config.js <<'EOF'
export default {
  plugins: {
    tailwindcss: {},
    autoprefixer: {},
  },
}
EOF
  cat > src/index.css <<'EOF'
@import "tailwindcss";
EOF
fi

# Ensure Tailwind config exists (required by shadcn)
if [ ! -f tailwind.config.ts ] && [ ! -f tailwind.config.js ]; then
  cat > tailwind.config.ts <<'EOF'
import type { Config } from "tailwindcss";

export default {
  content: ["./index.html", "./src/**/*.{js,ts,jsx,tsx}"],
  theme: { extend: {} },
  plugins: [],
} satisfies Config;
EOF
fi

# =========[ STEP 3: HARD-SET ALIASES ]=========
echo "Writing tsconfig.json with @ alias..."
cat > tsconfig.json <<'EOF'
{
  "compilerOptions": {
    "target": "ES2020",
    "useDefineForClassFields": true,
    "lib": ["ES2020", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "skipLibCheck": true,
    "jsx": "react-jsx",
    "moduleResolution": "Bundler",
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noEmit": true,
    "noUncheckedSideEffectImports": true,
    "esModuleInterop": false,
    "preserveValueImports": true,
    "allowImportingTsExtensions": true,
    "verbatimModuleSyntax": true,
    "strict": true,

    "baseUrl": ".",
    "paths": {
      "@/*": ["./src/*"]
    }
  },
  "include": ["src"]
}
EOF

echo "Writing Vite config with @ alias..."
cat > vite.config.ts <<'EOF'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { fileURLToPath, URL } from 'node:url'

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url))
    }
  }
})
EOF

# =========[ STEP 4: SHADCN/UI ]=========
echo "Installing and initializing shadcn/ui..."
bun add -d shadcn@latest >/dev/null
( bunx shadcn init -d || bunx --yes --package shadcn@latest shadcn init -d || npx --yes shadcn@latest init -d )

echo "Adding shadcn/ui components (no deprecated 'toast')..."
ADD_COMPONENTS=(
  button card input label textarea dropdown-menu navigation-menu accordion avatar
  badge alert dialog sheet tooltip skeleton progress tabs select switch
  checkbox radio-group slider separator scroll-area sonner
)

add_with_any_runner() {
  local component="$1"
  bunx shadcn add "$component" \
  || bunx --yes --package shadcn@latest shadcn add "$component" \
  || npx --yes shadcn@latest add "$component"
}

for comp in "${ADD_COMPONENTS[@]}"; do
  add_with_any_runner "$comp"
done

# =========[ STEP 5: GIT + IGNORE ]=========
echo "Initializing Git..."
git init >/dev/null 2>&1 || true
cat > .gitignore <<'EOF'
node_modules
bun.lockb
dist
.env
EOF

# =========[ DONE ]=========
echo
echo "───────────────────────────────────────────────"
echo "Project setup complete."
echo "cd $APP_NAME"
echo "bun dev"
echo "───────────────────────────────────────────────"
