# Changelog

All notable changes to the Tidewater v2 model, one section per baseline. The newest is first. Entries come from the
merge requests' `Changelog:` commit trailers (see the wiki page *Definition of Done*).

## [Unreleased]

### Added
- <!-- one line per MR: what changed, then the MR reference, e.g. "Hygrometer in the sensor suite (!57)" -->

### Changed

### Fixed

### Prime drops merged
- <!-- version, delivery date, intake issue, e.g. "v1.1, 2027-01-08 (#88)" -->

## [baseline-1] -- 2027-03-19

### Added
- The full Tidewater structure ported from prime drop v1.0: 12 packages, 40 part definitions (!3 to !21).
- Requirements from DOORS with their `doorsId`, and the satisfy/verify trace (!22 to !30).
- Hand-written SysML v2 for what the converter could not carry: the `BuoyModes` states, the `DailyUpload`
  sequence, the `EnergyBalance` constraint and the observation-cycle fork (!31 to !38).

### Prime drops merged
- v1.0, 2026-10-02 (#5)
- v1.1, 2027-01-08 (#61)

[Unreleased]: ../-/compare/baseline-1...develop
[baseline-1]: ../-/tags/baseline-1
