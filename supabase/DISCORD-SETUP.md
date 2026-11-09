# Discord bot: setup checklist

Once this is done, every event posted on the site shows up in your Discord channel with **Tank**, **Healer**, **DPS** and **Can't make it** buttons, its sign-up counts stay up to date, and an hour before it starts the bot replies with a reminder that pings everyone going. It's free: no server, just Supabase and GitHub.

It uses the Discord app you already made for "Sign in with Discord", so there's one app for both.

**In the Discord Developer Portal** (discord.com/developers/applications, open the guild's app):

1. **Make the bot.** Open the **Bot** page. Press **Reset Token**, then **Copy**, and keep the token somewhere private for step 6. On the same page, turn **Public Bot** off (so only you can add it to a server).
2. **Copy two keys.** Open the **General Information** page and copy the **Application ID** and the **Public Key**.
3. **Invite the bot.** Open the **OAuth2** page. Under **OAuth2 URL Generator**, tick **bot** and **applications.commands**. Under **Bot Permissions**, tick **View Channels**, **Send Messages**, **Embed Links** and **Read Message History** (leave **Mention Everyone** off). Copy the **Generated URL** at the bottom, open it, pick the guild's server and press **Authorize**.

**In Discord:**

4. **Copy the channel's id.** Open **User Settings** (the gear) > **Advanced** and turn on **Developer Mode**. Right-click the channel the events should go in and press **Copy Channel ID**. If the channel is private, add the bot to it: **Edit Channel** > **Permissions** > **Add members or roles**, and pick the bot.

**In Supabase and GitHub:**

5. **Let GitHub deploy the bot.** In Supabase, open your account's **Access Tokens** page (supabase.com/dashboard/account/tokens), press **Generate new token**, name it `GitHub` and copy it. In the GitHub repo, open **Settings** > **Secrets and variables** > **Actions**, the **Secrets** tab, press **New repository secret**, name it `SUPABASE_ACCESS_TOKEN` and paste the token.
6. **Give the bot its keys.** In the Supabase project, open **Edge Functions** > **Secrets** and add these four (name, then value), then save:
   - `DISCORD_BOT_TOKEN`: the token from step 1
   - `DISCORD_PUBLIC_KEY`: the Public Key from step 2
   - `DISCORD_APPLICATION_ID`: the Application ID from step 2
   - `DISCORD_CHANNEL_ID`: the channel id from step 4
7. **Deploy it.** In the GitHub repo, open the **Actions** tab, pick **Deploy the Discord bot** on the left, press **Run workflow**, then the green **Run workflow**. Wait for the green tick (a couple of minutes).
8. **Connect the buttons.** Back in the Developer Portal's **General Information** page, paste this into **Interactions Endpoint URL** and press **Save Changes**:
   `https://nwxgcmcgmsvbnvolthrd.supabase.co/functions/v1/discord-interactions`
   Discord checks it straight away. If it says it can't verify the URL, step 6 or 7 isn't finished yet.
9. **Switch it on.** In Supabase, open **SQL Editor** > **New query**, paste all of `supabase/discord-bot.sql` from the repo and press **Run**. The upcoming events appear in the channel within a minute.
10. **Try it.** Post a test event on the site's **Events** page: it appears in Discord. Press **Healer** under it: only you see "You're in as Healer…", and the count goes up. Delete the test event on the site: the post goes too.

**Good to know**

- The event form on the site shows a small Discord logo: bright once the event is posted in Discord, faded until then.
- Someone who hasn't signed in on the site yet, or is still waiting for approval, gets a short note with the site's link when they press a button.
- A button signs people up with a character that plays that role (their main first), else their main.
- Change how long before the start the reminder goes out (in minutes) with this in the **SQL Editor**: `update public.discord_state set reminder_minutes = 30;`
- Switch the bot off with: `update public.discord_state set functions_url = null;` (paste `discord-bot.sql` again to switch it back on).
- If posts stop appearing: Supabase **Edge Functions** > **discord-announce** > **Logs** says why (most often a missing secret, or the bot can't see the channel).
