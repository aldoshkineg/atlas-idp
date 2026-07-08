# Disabled layer wrappers

Move a layer wrapper **here** (via `git mv`) to disable the layer.

`root-app` renders `gitops/platform/layers/` **non-recursively**, so wrappers
in this subfolder are ignored and will not be recreated on the next
reconcile. This is the honest off-switch: a disabled layer stays off until
someone explicitly moves the wrapper back.

```bash
# Disable
git mv gitops/platform/layers/<layer>.yaml gitops/platform/layers/disabled/

# Enable (bring the layer back)
git mv gitops/platform/layers/disabled/<layer>.yaml gitops/platform/layers/
```

> The layer's contents (`gitops/platform/<layer>/`) stay in place — only the
> wrapper moves, so re-enabling is trivial.
>
> To also remove the already-running layer from the cluster, run once:
> `argocd app delete <layer> --cascade`
