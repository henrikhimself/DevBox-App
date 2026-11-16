# F45 - forward passes IdentityFile only for existing readable keys

1. Start a running fixture container for profile `tplanfwdid`.
2. Run `./forward.sh` with a fake `ssh` shim and a fake `HOME` that has no key files.
3. Verify the logged ssh arguments contain no `IdentityFile=...` options.
4. Add one readable key file (`~/.ssh/id_ed25519`) in fake `HOME`.
5. Run `./forward.sh` again and verify exactly one `IdentityFile` option is passed, and it points to that key.
