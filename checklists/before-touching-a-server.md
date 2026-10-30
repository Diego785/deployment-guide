# Before touching a server

- [ ] I know who owns the server and what I'm allowed to touch.
- [ ] I can log in (key or password typed by hand) and I know my user (`id`).
- [ ] I ran the inventory and saved the output ([02](../docs/02-inventory.md)).
- [ ] I know: projects folder, proxy container, its config and certificates folders, shared
  network, certificate renewal method, ports and names in use.
- [ ] `nginx -t` passes **today**, before any change of mine.
- [ ] There's enough disk and memory for what I'll add.
- [ ] For each change I plan, I know how to check it and how to undo it.
- [ ] I'll only use my folder and my `.conf`; no global prunes, no nginx restart.
