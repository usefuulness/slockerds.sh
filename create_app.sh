#!/usr/bin/env bash
set -euo pipefail

APP_NAME=${1:-my-app}

# ===== Banner =====
cat <<'BANNER'
───────────────────────────────────────────────
   _____ _            _                _     
  / ____| |          | |              | |    
 | (___ | | ___   ___| | _____ _ __ __| |___ 
  \___ \| |/ _ \ / __| |/ / _ \ '__/ _` / __|
  ____) | | (_) | (__|   <  __/ | | (_| \__ \
 |_____/|_|\___/ \___|_|\_\___|_|  \__,_|___/
───────────────────────────────────────────────
 React + Bun + Tailwind v4 + shadcn/ui + Supabase (optional)
───────────────────────────────────────────────
BANNER

# ===== Prechecks =====
need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1" >&2; exit 1; }; }
need_cmd git
need_cmd bun

if [ -e "$APP_NAME" ]; then
  echo "Target path '$APP_NAME' already exists. Choose another name or remove it." >&2
  exit 1
fi

# ===== Base project (no prompts) =====
echo "Creating Vite + React + TS project..."
TMP_DIR="$(mktemp -d)"
git clone --depth 1 https://github.com/vitejs/vite.git "$TMP_DIR" >/dev/null
cp -R "$TMP_DIR/packages/create-vite/template-react-ts" "$APP_NAME"
rm -rf "$TMP_DIR"
cd "$APP_NAME"

# Name the package
if command -v jq >/dev/null 2>&1; then
  tmp=$(mktemp)
  jq --arg name "$APP_NAME" '.name=$name' package.json > "$tmp" && mv "$tmp" package.json
else
  sed -i 's/"name": *"[^"]*"/"name": "'"$APP_NAME"'"/' package.json || true
fi

echo "Installing base deps..."
bun install

# ===== Tailwind v4 + core deps =====
echo "Adding Tailwind v4 + PostCSS and core deps..."
bun add -d tailwindcss @tailwindcss/postcss postcss autoprefixer tailwindcss-animate
bun add react-router-dom class-variance-authority tailwind-merge lucide-react

mkdir -p src

# Minimal CSS (v4 ordering: @import first, then @plugin)
cat > src/index.css <<'EOF'
@import "tailwindcss";
@plugin "tailwindcss-animate";
/* Custom CSS can follow */
EOF

# Ensure stylesheet import
if ! grep -q "import './index.css'" src/main.tsx 2>/dev/null; then
  sed -i "1i import './index.css'" src/main.tsx
fi

# PostCSS config for Tailwind v4
cat > postcss.config.js <<'EOF'
import tailwindcss from '@tailwindcss/postcss'
import autoprefixer from 'autoprefixer'

export default {
  plugins: [tailwindcss(), autoprefixer()],
}
EOF

# Tailwind config (needed by shadcn preflight)
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

# ===== Hard-set aliases =====
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
    "paths": { "@/*": ["./src/*"] }
  },
  "include": ["src"]
}
EOF

# Vite config with polling to avoid fs watcher issues on some filesystems
echo "Writing Vite config with @ alias and polling watcher..."
cat > vite.config.ts <<'EOF'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { fileURLToPath, URL } from 'node:url'

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) }
  },
  server: {
    watch: {
      usePolling: true,
      interval: 150,
    },
    fs: { strict: false },
  }
})
EOF

# ===== Supabase (optional client) =====
echo "Adding Supabase packages (client is optional at runtime)..."
bun add @supabase/supabase-js @supabase/auth-helpers-react

cat > .env.example <<'EOF'
VITE_SUPABASE_URL=
VITE_SUPABASE_ANON_KEY=
EOF

if [ ! -f .env ]; then
  cat > .env <<'EOF'
# Optional: fill when you want Supabase enabled
VITE_SUPABASE_URL=
VITE_SUPABASE_ANON_KEY=
EOF
fi

mkdir -p src/lib/supabase
# Optional client: only create when both vars exist
cat > src/lib/supabase/client.ts <<'EOF'
import { createClient, type SupabaseClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL as string | undefined
const anon = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined

export const supabase: SupabaseClient | null =
  url && anon ? createClient(url, anon) : null
EOF

# main.tsx: wrap App in SessionContextProvider only if supabase exists
cat > src/main.tsx <<'EOF'
import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App.tsx'
import './index.css'

import { SessionContextProvider } from '@supabase/auth-helpers-react'
import { supabase } from '@/lib/supabase/client'

const Root = (
  <React.StrictMode>
    {supabase ? (
      <SessionContextProvider supabaseClient={supabase}>
        <App />
      </SessionContextProvider>
    ) : (
      <App />
    )}
  </React.StrictMode>
)

ReactDOM.createRoot(document.getElementById('root')!).render(Root)
EOF

# ===== shadcn/ui =====
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

# ===== Minimal landing page =====
echo "Writing minimal index page (App.tsx)..."
cat > src/App.tsx <<'EOF'
import { useState } from 'react'
import { Button } from '@/components/ui/button'
import { Card, CardHeader, CardTitle, CardDescription, CardContent } from '@/components/ui/card'
import { Toaster } from '@/components/ui/sonner'
import { Github, Rocket } from 'lucide-react'

export default function App() {
  const [count, setCount] = useState(0)

  return (
    <div className="min-h-screen grid place-items-center bg-background text-foreground p-6">
      <Card className="w-full max-w-xl">
        <CardHeader className="text-center">
          <CardTitle className="text-2xl font-semibold">Vite + React + Tailwind</CardTitle>
          <CardDescription>shadcn/ui wired · Supabase optional</CardDescription>
        </CardHeader>
        <CardContent className="flex flex-wrap gap-2 justify-center">
          <Button onClick={() => setCount((v) => v + 1)}>
            <Rocket className="mr-2 h-4 w-4" />
            Get started ({count})
          </Button>
          <a href="https://vitejs.dev/" target="_blank" rel="noreferrer">
            <Button variant="outline">Vite</Button>
          </a>
          <a href="https://tailwindcss.com/" target="_blank" rel="noreferrer">
            <Button variant="outline">Tailwind</Button>
          </a>
          <a href="https://ui.shadcn.com/" target="_blank" rel="noreferrer">
            <Button variant="outline">shadcn/ui</Button>
          </a>
          <a href="https://supabase.com/docs" target="_blank" rel="noreferrer">
            <Button variant="ghost">Supabase</Button>
          </a>
          <a href="https://github.com/usefuulness/slockerds.sh" target="_blank" rel="noreferrer">
            <Button variant="ghost">
              <Github className="mr-2 h-4 w-4" />
              GitHub
            </Button>
          </a>
        </CardContent>
      </Card>
      <Toaster />
    </div>
  )
}
EOF

# Normalize index.css ordering for Tailwind v4 (imports first, then plugin)
if grep -q '@import "tailwindcss"' src/index.css 2>/dev/null; then
  TMP_CSS="$(mktemp)"
  {
    echo '@import "tailwindcss";'
    echo '@plugin "tailwindcss-animate";'
    awk '!/^@import "tailwindcss";/ && !/^@plugin "tailwindcss-animate";/ && !/^@import "tw-animate-css";/ {print}' src/index.css
  } > "$TMP_CSS"
  mv "$TMP_CSS" src/index.css
fi

# ===== Git + ignore =====
echo "Initializing Git..."
git init >/dev/null 2>&1 || true
cat > .gitignore <<'EOF'
node_modules
bun.lockb
dist
.env
EOF

echo
echo "───────────────────────────────────────────────"
echo "Project setup complete."
echo "cd" "$APP_NAME"
echo "bun dev"
echo "───────────────────────────────────────────────"
