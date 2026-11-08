# Fantasy Force

The website of Fantasy Force, a Horde guild in World of Warcraft: Forever: who's in it, their mains and alts, professions, events with sign-ups, when everyone plays, and how the classes and roles balance out. Members sign in with Discord and bring their characters in from the Fantasy Force addon (or add them by hand). Officers approve newcomers, set ranks, post events and keep private notes.

## Pages

- **Roster:** everyone, with their main and alts, level, rank, professions and local time. Search and filter by class, role or rank.
- **Professions:** who has each profession, highest skill first: where to find a crafter.
- **Events:** raids and other events. Members sign up with a character and a role (Going, Maybe or Can't make it), and each event shows tanks, healers and DPS against what's needed.
- **Availability:** each member paints the hours they usually play. The guild heat map and the best three-hour raid times show in each viewer's own time zone.
- **Class balance:** tanks, healers and DPS among mains, how many players can fill each role on any character, and every class's mains and alts.
- **My characters:** your profile (name, time zone) and characters. Drop the addon's saved file here to bring every character in, with level, race, spec and professions. Pick one as your main.
- **Officers:** approve or turn away new sign-ins, set ranks and join dates, keep officer-only notes, see the in-game guild list (and who isn't on the site yet), edit ranks and guild settings.

## The addon

`addon/FantasyForce/` is a small addon for WoW Forever. It records each character you log in on (level, class, race, spec, professions, guild rank) and the guild's in-game roster into its saved file, `World of Warcraft\_forever_\WTF\Account\<ACCOUNT>\SavedVariables\FantasyForce.lua`, written when you log out or type `/reload`. No UI and no network; `/ff` says what it has recorded. It never records officer notes. `addon/example-FantasyForce.lua` is a sample file for trying the import.

**Publishing it on CurseForge** (once): create a CurseForge account and a new WoW project named Fantasy Force, and note its project id. Under the GitHub repo's Settings > Secrets and variables > Actions, add the variable `CF_PROJECT_ID` and the secret `CF_API_KEY` (a CurseForge API token, from your CurseForge account's API tokens page). Then each release is a tag: `git tag addon-v1.0.0 && git push --tags`, and the workflow packages the addon and uploads it, so members' CurseForge app updates it.

## Try the demo

```
npm install
npm run dev
```

Without Supabase settings the site runs as a demo: an example guild kept in your browser. Use "Viewing as" in the top bar to see it as a visitor, a member, an officer, or someone waiting for approval.

## Going live

It's free: Supabase's free tier holds the data and handles Discord sign-in, and GitHub Pages hosts the site.

1. **Supabase project.** Sign up at supabase.com, then create a new project. Under **SQL Editor**, paste all of `supabase/schema.sql` and press Run. Under **Project Settings > API**, copy the **Project URL** and the **anon public** key.
2. **Discord app.** At discord.com/developers/applications, create a New Application. Under **OAuth2**, copy the Client ID and reset/copy the Client Secret, then add this redirect: `https://YOUR-PROJECT.supabase.co/auth/v1/callback`.
3. **Discord in Supabase.** In Supabase under **Authentication > Sign In / Providers > Discord**, turn it on and paste the Client ID and Secret.
4. **Your site's address.** In Supabase under **Authentication > URL Configuration**, set the Site URL to where the site will live (for example `https://yourname.github.io/guild-roster/`) and add it to the Redirect URLs.
5. **Publish.** Push this folder to a GitHub repo. Under **Settings > Pages**, set Source to **GitHub Actions**. Under **Settings > Secrets and variables > Actions > Variables**, add `SUPABASE_URL` and `SUPABASE_ANON_KEY`. Each push to `main` then rebuilds the site.
6. **Make yourself Guild Master.** Sign in on the site once, then run in Supabase's SQL Editor:
   ```sql
   update public.members set rank_id = (select id from public.ranks order by sort limit 1)
   where display_name = 'YourDiscordName';
   ```
   Everything else (guild name, realm, ranks, approving members) is done on the site's Officers page.

## Who can see and change what

The rules live in the database (`supabase/schema.sql`), so they hold whatever the website does.

- **Anyone:** the guild, approved members and their characters, availability, events and sign-ups.
- **Signed in:** your own profile, characters and week. Once approved, you can sign up for events with your own characters.
- **Officers** (any rank marked Officer): all of the above for anyone, plus approvals, ranks, events, and officer notes. Only officers can read officer notes.
- Nobody can change their own rank.

## Code

Vite, React and TypeScript. `src/store/` is the one data layer, with two backends: `demo.ts` (the browser) and `supabase.ts` (live). `src/wow.ts` holds classes, specs, roles and class colours. `npm test` runs the unit tests and `npm run build` makes `dist/`.
