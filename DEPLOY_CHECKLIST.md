# Deployment Checklist

- [ ] Create the Supabase project.
- [ ] Run `supabase/schema.sql` once in the SQL editor.
- [ ] Disable public sign-ups in Supabase Auth.
- [ ] Push this folder to your own GitHub repository.
- [ ] Import that repository into Vercel and set the three environment variables from `.env.example`.
- [ ] Set Supabase Auth Site URL / Redirect URLs to the Vercel domain, including `/auth/callback`.
- [ ] Invite your own email from Supabase Auth and promote it to `admin` with the SQL command in README.
- [ ] Open the email link, sign in, then use Team access to invite your other users.
- [ ] Test viewer vs editor permissions with two accounts before sharing the link widely.
