# shorty.memory

A retro CRT-inspired little universe for two people. This folder is a standalone website and does not replace the root \`little-garden\` site.

## Included

- CRT / ASCII terminal landing screen with simple unlock-style commands
- Responsive couple dashboard, relationship date counter, daily notes, and random movie picker
- Profile editing and profile-picture upload
- People directory and friend-request flow
- Pair invitation codes (24-hour expiry) and pair linking
- Memory vault with photo upload and captions
- Animated “Open When…” letters and floating Shorty mascot
- Browser-local demo mode, plus optional Supabase authentication, database, and storage
- Supabase schema with Row Level Security policies

## Run locally

Open \`index.html\` in a browser, or use a local static server from the repository root, for example:

\`\`\`bash
python -m http.server 8000
\`\`\`

Then visit \`http://localhost:8000/shorty-memory/\`.

The site uses Google Fonts and the Supabase JS CDN, so those resources need internet access. Without Supabase configuration, the app runs in **local preview mode**.

## Local preview limitations

Local preview is for interface and interaction testing only. Demo profiles, requests, pair links, and memories are saved in the current browser's localStorage. They are not synchronized to another computer or browser. Do not use real passwords or sensitive/private photos in local preview. The demo password hash is a convenience for local testing, not server authentication.

To try requests and pairing locally, create two different demo accounts in the same browser and sign in to each in turn. A second device cannot accept that browser-local pair code.

## Enable real accounts and cross-device data (Supabase)

1. Create a Supabase project.
2. In **Authentication → URL Configuration**, add your local and deployed website URLs. Configure email confirmation according to your needs.
3. Open the Supabase SQL Editor and run \`supabase/schema.sql\` in full.
4. Create two Storage buckets named \`avatars\` (public) and \`memory-photos\` (private). The schema file creates bucket definitions and policies where supported; verify both buckets exist under **Storage**.
5. Open \`config.js\`. Set \`supabaseUrl\` and the browser-safe **anon/publishable** key from your project's API settings.
6. Never use the \`service_role\` key in \`config.js\` or any browser-delivered file.
7. Reload the page and create accounts. Email verification may be required before login.

Supabase has to be configured separately; the website does not create a cloud project or deploy itself. Check Authentication, SQL, Storage, and Row Level Security logs if a request is rejected.

### Security notes

- Database tables use Row Level Security. The website public profile directory intentionally exposes display name, username, bio, avatar URL, and timestamps to authenticated users; do not put private information in those fields.
- Avatar URLs are public by design. Memory photos use a private bucket and temporary signed URLs. A person who can view a shared memory can access its signed URL until it expires.
- Pair codes should be shared privately. They are short-lived and single-use.
- This is a starter application, not an audited production service. Before real-world use, add abuse limits, email/username moderation, report/block flows, data export/deletion, backup/retention policies, and security review.

## Deployment

The site is static and can be published with GitHub Pages or another static host. For GitHub Pages, set the source to the branch containing this repository and keep the project under \`/shorty-memory/\`. Since this repository is already a public repository, do not commit private data. After setting the Supabase URL allow-list, open:

\`https://velox-lap.github.io/little-garden/shorty-memory/\`

The exact GitHub Pages URL depends on the Pages settings and successful deployment.

## Customize

- \`styles.css\`: colors, layout, terminal/CRT effects, responsiveness
- \`app.js\`: commands, demo behavior, letters, daily notes, movie choices, mascot lines
- \`config.js\`: public Supabase project settings
- \`supabase/schema.sql\`: database schema, RLS policies, storage access rules, pair-code RPC

