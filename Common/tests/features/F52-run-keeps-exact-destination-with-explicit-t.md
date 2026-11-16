# F52 - an explicit -t keeps the exact-destination behavior

1. Make sure `./init.sh` and `./run.sh` are on present in the repository.
2. Create a workspace directory named `my-project` and run `./run.sh -p 2223 -t /code -v tplanwsexact <...>/my-project` with a fake `container` command in `PATH`.
3. Verify the `container run` invocation uses the exact destination `-v <ws>:/code` (no project-name subdirectory) and the label `devbox.workspace-target=/code`.
4. Verify the announcement line reads `Bind-mounting <ws> → /code`.
