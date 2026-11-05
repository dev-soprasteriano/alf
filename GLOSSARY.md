# Skill assets

The plugin's catalogue of upstream skills. It keeps each upstream skill as a pinned asset and exposes it through a wrapper skill that can add local instructions.

## Assets

**Upstream**:
A GitHub repository that assets are copied from. Each upstream has its own folder in the catalogue, with its license and its pin record.
_Avoid_: Source, origin

**Asset**:
A byte-for-byte copy of one skill folder from an upstream. An update replaces it in full.
_Avoid_: Vendored skill, copy

**Catalogue**:
The set of all assets, grouped by upstream.
_Avoid_: Library, registry

**Pin**:
The revision an asset is fixed at. A pinned asset is skipped by the weekly update until it is moved to latest.
_Avoid_: Lock, freeze

**Latest**:
The newest revision on an upstream's default branch that changes an asset's folder.

## Skills

**Wrapper**:
A plugin skill that points at one asset and adds the overlay. The asset is the skill being wrapped.
_Avoid_: Alias, proxy

**In-house skill**:
A plugin skill written in this repo, with no asset behind it.
_Avoid_: Full skill, standalone skill

**Overlay**:
Local instructions a wrapper adds after following its asset.
_Avoid_: Patch, customisation

**Dependency**:
A skill that another skill calls by name or links to.
_Avoid_: Requirement, related skill
