# Developer documentation

Here we discuss some of the internal details of PackageAnalyzer.jl, for anyone interested,
and to facilitate maintenance and future development.

## Flow

Let's look at how we move through the code from the two main entrypoints, `analyze`, or `analyze_manifest`.

### Constructing a `PkgSource`

First, we construct a `PkgSource`. This is an abstract type representing the possible metadata we have describing
the package (and what version of it) we wish to analyze. PackageAnalyzer provides the following subtypes of `PkgSource`.

Note: here we will briefly describe the most relevant fields, omitting ones that aren't crucial for obtaining the correct code to analyze.

* `Release`. This contains the package's UUID, repo url, subdirectory (if any), and the tree hash of the package code.
* `Dev`. This holds a (local) `path` pointing to a directory of source code to analyze. It is named thus because `dev`'d dependencies
  (from `Pkg.develop`) in manifests are tracked this way. No tree hash or version is stored; rather, whatever code is located
  at the path is analyzed. This is similar to how Pkg treats dev'd dependencies.
* `Added`. This holds either a local `path` to a git repo or a URL pointing to a remote git repo, along with a UUID and tree hash. It is
  named thus because it represents `Pkg.add`'d dependencies which are not release versions (e.g. when using Pkg to add a package with a specific commit or branch).
* `Trunk`. This holds a remote repo url and a subdirectory, and corresponds to the latest version of the code on the trunk branch of the
  remote repository. This does not correspond to any `Pkg` operation, but was the only supported behavior before PackageAnalyzer v1.0.

`analyze` constructs a `PkgSource` directly by parsing the user's input. For some examples:

* Passing a module, e.g., `analyze(PackageAnalyzer)`, results in a `Dev` object tracking `pkgdir(PackageAnalyzer)`.
* Passing a string `name` that satisfies `Base.isidentifier(name)===true`, such as `"PackageAnalyzer"`, results in
  a `Release` object associated to the latest release found in any installed registry. In the code, this is facilitated
  by the function `find_package` with the `version` keyword argument set to the special symbol `:stable`, meaning the latest release.
* Passing a string that does not satisfy `Base.isidentifier` but does satisfy `isdir` results in a `Dev` object tracking the path.
* Any other string is guessed to be a URL, and a `Trunk` object is used to track the remote URL.

`analyze_manifest`, on the other hand, parses a `Manifest.toml`, and for each package found, builds either a `Release`, `Dev`,
or `Added`, depending on what fields are present in the manifest for that object, using `find_packages_in_manifest`.

Additionally, `find_package` (or `find_packages`) can be used directly by the user to create a `PkgSource`. This provides
some additional flexibility, e.g. passing a package UUID for disambiguation, and avoids the need to parse the user input.

Note: currently if only a string named is used and two packages with the same name different UUIDs are present (in different registries),
those packages will be conflated (and e.g. the one with the latest version number will be chosen).

Note also that all installed registries are treated equally (e.g. General is not preferred over others),
and are used to find releases of a given package.

To summarize: `analyze` and `analyze_manifest` calls create `PkgSource`'s (often with the held of `find_package` or `find_packages_in_manifest`),
which are passed back to `analyze` (which has dispatches for each subtype of `PkgSource`).

This section covered the broad strokes of `src/find_packages.jl` and the first half of `src/analyze.jl`, along with `PkgSource` definitions
in `src/PackageAnalyzer.jl`.

### Obtaining code

When `analyze` is called on a `PkgSource` subtype, it first calls `obtain_code`. The job of `obtain_code` is to place the desired source code
in a local directory, and return that directory along with `reachable` corresponding to whether or not the operation was successful.
