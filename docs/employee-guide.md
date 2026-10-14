# Employee guide

For people using the chat platform. No technical knowledge needed.

## Getting access

1. Ask the administrator to add your public IP to the allow-list. Find it at
   [api.ipify.org](https://api.ipify.org) and send it to them.
2. Wait for them to confirm.
3. Open the site address the administrator gives you, for example
   `https://<the address your administrator gives you>`.

> **Your browser will show a warning** the first time, something like
> "Your connection is not private" or "NET::ERR_CERT_AUTHORITY_INVALID".
> This is expected. The site uses a private certificate rather than one issued
> by a public authority, because it is restricted to a known list of IP
> addresses. Click **Advanced** → **Continue** to proceed. Your traffic is
> still encrypted.

If the page never loads at all, your IP is probably not on the list yet — tell
the administrator, along with the IP from step 1.

## Signing in

Enter the email address and password the administrator gave you, then **Sign
in**.

## Waiting for approval

New accounts are created in a **pending** state. Until an administrator
approves it, you can sign in but cannot chat — you will see a message saying
your account is waiting for approval. The administrator approves accounts in
the admin panel. You do not need to do anything except wait.

## Having a conversation

Type a message in the box at the bottom and press **Enter**. Use
**Shift + Enter** for a new line without sending.

- **New chat** starts a fresh conversation.
- The **sidebar** lists your previous chats; click one to reopen it.
- **Stop** (the square button) cancels a reply that is taking too long.

## Uploading a document

Drag a file into the message box, or click the **+** next to it. Supported
formats include PDF, Word documents, text and Markdown files.

Once uploaded, ask questions about it directly, such as:

- "Summarise this document."
- "What are the key dates in this contract?"
- "List the action items for my team."

Uploaded documents are stored on the platform's server. **Do not upload
anything confidential** — it persists on the server, and administrators can
access the server.

## Changing your password

**Settings** (the icon in the sidebar) → **Account** → **Password**.

## Things that will not work, and why

| If you see | It means |
|---|---|
| "You do not have permission" on every action | Your account is still pending approval |
| A "Sign up" button, but you cannot chat | Registration is open, but new accounts need admin approval before they can do anything |
| Nothing loads when you click a link | Connection issue — see below |
| Certificate warning every time | Expected for this deployment; bypass it once per browser |

## When the site is offline

The server is switched off automatically every night at **22:00 (Arab Standard
Time)** to keep hosting costs down. If the site is unreachable outside working
hours, it may just be switched off — contact the administrator.

## Privacy

- Prompts, responses, and uploaded documents are stored on the platform's
  server, not in your browser.
- Administrators can access that server and its contents.
- The platform sends your prompts to the Azure OpenAI service to generate
  replies.
- Chats survive restarts and server reboots, but they are not backed up
  off-site automatically.

## Asking for help

Give the administrator:

1. What you were doing.
2. The exact message, copied and pasted.
3. A screenshot.
4. The result of opening `https://api.ipify.org` in the same browser, so they
   can check your IP is still allowed.

## Frequently asked

**Can I invite colleagues?**
Yes — if their public IP is already allowed, they can register themselves using
the **Sign up** button on the login page. Their account will be waiting for
approval until an administrator accepts it. If their IP is not allowed, the
site will not load for them at all, so send it to the administrator first.

**Can I use this on my phone?**
Yes, if your phone's public IP is on the allow-list. Note that mobile networks
frequently change IP addresses, so access can stop working without warning —
ask the administrator to allow your mobile network's range.

**Can I get the app for my phone or laptop?**
No. It is a web application; use a browser.

**Why is it so slow sometimes?**
The server is small and is switched off overnight. Start-up after it has been
off takes a minute or two.

**Can I use a different language?**
The interface follows your browser's language setting where supported.