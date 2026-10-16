# PrintOps — 3D Printing Production Tracker

A shared Next.js + Supabase web app for tracking the T4, X4B, X2C and Lanyard Stand production lists. It supports four internal printers (`P1`–`P4`), outside printing (default vendor: Fraxus), item-level print settings, print-job status, quantity completion, and invite-only workspace access.

## How quantity tracking works

- `Required` is the target quantity stored on each item.
- `Completed` is calculated from the `completed_quantity` on print jobs for that item.
- Marking a job `Completed` automatically sets its completed quantity to the planned quantity in the database, so the item totals refresh automatically.
- Marking a job `Failed` sets its completed quantity to zero. Create a new job for the reprint; failed batches do not increase the completed count.
- The app allows partially completed quantities for jobs still queued/printing (edit the Done Qty field in the job table).
- A database index prevents two jobs from simultaneously being marked `Printing` on the same printer. Queued jobs can share a printer.
- Roles: `admin` manages invitations and member roles; `editor` edits production; `viewer` has read-only access.
- The workbook included target quantities/settings for 10 items. Two Lanyard Stand item quantities/settings were missing; `Flower` and `Connect Joint` are seeded with target quantity 0 and can be completed in the Item Settings dialog. The workbook did not contain current completion counts, so completed quantities start at zero until you record completed jobs or backfill known completed amounts.

## Architecture

- **App:** Next.js App Router, TypeScript, React.
- **Database + authentication:** Supabase Postgres + Supabase Auth.
- **Hosting:** Deploy this Next.js app on Vercel connected to GitHub. GitHub Pages alone is a static host and is not suitable for the invitation API route used by this app.
- **Access:** Supabase Row Level Security protects every production table. The service-role key is used only in `/api/invite` on the server; never expose it in browser code or commit it to GitHub.

## 1. Create the Supabase database

1. Create a Supabase project at <https://supabase.com/dashboard>.
2. Open **SQL Editor → New query**.
3. Paste and run all of [`supabase/schema.sql`](./supabase/schema.sql). This creates the schema, security policies, one-active-print-job-per-printer rule and starter product/item data from the uploaded workbook. The item seeds use `ON CONFLICT DO NOTHING`; running it again will not overwrite edited item settings/quantities.
4. In **Authentication → Providers**, enable Email sign-in. In **Authentication → URL Configuration**, set the Site URL to your future Vercel domain and add both your production callback and local callback to the Redirect URLs allow-list, for example:
   - `https://YOUR-APP.vercel.app/auth/callback`
   - `http://localhost:3000/auth/callback`
5. In Authentication settings, disable public sign-ups / new user sign-ups. Access should be granted via an invitation only.

## 2. Set up the first admin

The first workspace admin needs to be bootstrapped once from Supabase:

1. After you have the app domain set up, open **Authentication → Users → Invite user** in Supabase and invite your own work email.
2. Before using the emailed link, open **SQL Editor** and run this, replacing the email with the same invited email:

   ```sql
   update public.app_members
   set role = 'admin'
   where lower(email) = lower('you@company.com');
   ```

3. Open the invitation email on the deployed app. You can then use **Team access** to invite teammates and assign `Editor` or `Viewer` access.

> If you already have a signed-in user but it isn't in `app_members`, don't enable public registration as a workaround. Make sure you invited that email through Supabase Auth and that the `app_members_after_insert_auth_user` trigger exists.

## 3. Push the project to GitHub

1. Extract the project ZIP and create a new empty repository in your GitHub account/organization.
2. From the extracted folder, run:

   ```bash
   git init
   git add .
   git commit -m "Add PrintOps production tracker"
   git branch -M main
   git remote add origin https://github.com/YOUR-ORG/YOUR-REPO.git
   git push -u origin main
   ```

3. Do not commit a real `.env` or `.env.local`. The `.gitignore` excludes both.

## 4. Deploy with Vercel

1. Open <https://vercel.com/new> and import the GitHub repository.
2. In **Project Settings → Environment Variables**, set:
   - `NEXT_PUBLIC_SUPABASE_URL` — Supabase Project URL.
   - `NEXT_PUBLIC_SUPABASE_ANON_KEY` — Supabase anon/publishable key.
   - `SUPABASE_SERVICE_ROLE_KEY` — Supabase service-role key (server-only secret).
3. Deploy. The generated Vercel URL is the shareable app link. Use that one link for teammates; only invited and authenticated members can see data.
4. Add the Vercel URL plus `/auth/callback` to Supabase Auth Redirect URLs and ensure the Site URL is the app root.

For local development, copy `.env.example` to `.env.local`, fill those same values and run:

```bash
npm install
npm run dev
```

Open <http://localhost:3000>.

## 5. Invite access model

- **Admin:** sees Team access and can invite a teammate by email; invite API checks the signed-in user's role on the server before using the service-role key. Admin can also change roles.
- **Editor:** can add/edit item settings and create/update print jobs.
- **Viewer:** can view the dashboard, production list, printer assignments and jobs but cannot change data.

Supabase RLS is the actual security boundary; hiding edit buttons in the UI is not relied on for security.

## Starter data loaded from the Excel

| Product | Item | Required quantity |
|---|---|---:|
| T4 | T4 Mask | 1 |
| T4 | Fanfold Tray | 10 |
| X4B | Front Cladding | 28 |
| X4B | Roller Shutter Mount | 35 |
| X4B | Roller Shutter | 37 |
| X4B | Cap Cladding - 16 piece | 4 |
| X4B | Tablet Holder | 30 |
| X2C | Front Cladding | 68 |
| X2C | Tablet Holder | 68 |
| X2C | Cap Cladding - 16 piece | 8 |
| Lanyard Stand | Flower | 0 — not provided in workbook |
| Lanyard Stand | Connect Joint | 0 — not provided in workbook |

The 10 supplied quantities sum to 289 units. Weights, per-part printing hours, infill, wall loops, ironing and PLA material labels are also prefilled from the workbook for those 10 items.

## Notes

- This ZIP is the complete app source. No public production URL can be created from this workspace itself: you need to connect the repo to your own GitHub/Vercel and Supabase projects and add their secrets. Once deployed, Vercel supplies the shareable URL.
- If using a custom domain, update the Supabase Auth Site URL / Redirect URL allow-list accordingly.
- Keep the Supabase service-role key private. Rotate it immediately if it is ever committed or shared.
