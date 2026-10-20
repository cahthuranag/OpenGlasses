# Rule chains

Write your organisation's rule chains in this file, against the table and rule numbers of your own code and edition. The three chains below are an invented example, the one the vault guide walks through: every table, rule, designation and value in them is made up, and they are listed as needing Tables 90, 98, 99 and 97 until a loaded book prints tables with those labels. Replace them with your own, or delete them.

Each chain is a level-two heading (its name), an Answers: line saying what it answers, then its steps, one per line, in a fenced block. Lines in a block that begin with // are comments. The steps:

    ask <name> (<unit>) range <low>..<high>: <what to ask>      a number from the technician
    ask <name> (text): <what to ask>                            words, such as a size as the table prints it
    lookup <name> = <table> row <row> column <column> rule <exact|at_least|at_most>
    lookup <name> = <table> column <column> cell <number> rule <exact|at_least|at_most>
    calc <name> (<unit>) = <expression>                         + - * / ( ), sqrt( ), names and numbers
    convert <name> = <name, or a number with its unit> to <unit>
    check <expression> <op> <expression> ? "<if true>" : "<if false>"     <, <=, >, >=, ==, !=
    cite <the rule as your book prints it>                       attaches to the step above
    say "<the result, with {name} for a value>"

A value is used by its name, in braces inside a heading or a sentence: {load}. A looked-up value also has {name.row}, {name.column}, {name.table}, {name.page} and {name.next}; any value has {name.unit}. A name is set once and used only after the step that sets it. Name a table as it is printed (Table 98), never from a value.

Voltage drop is arithmetic over named values: 2 * current * length * resistance for a single-phase run, sqrt(3) * current * length * resistance for a three-phase run, with the resistance per unit length in the same length unit as the run (divide by 1000 for a resistance per km with a length in metres). A factor over the conductor's area works the same way: 2 * factor * current * length / area. The resistance or the factor comes from a lookup in your own book or from the technician, never from the app.

## Example: size a conductor for a load
Answers: an invented example over made-up tables — which conductor carries a load once it is corrected for the ambient temperature and the conductors grouped in the run.

```chain
// Four values from the technician, each with its unit and the range accepted.
ask load (A) range 1..400: What load will the circuit carry, in amps?
ask ambient (°C) range 0..40: What is the ambient temperature along the run?
ask conductors (conductors) range 1..9: How many current-carrying conductors share the run?
ask group range 1..3: Which rating group is the installation method in?
// The band the grouping falls in, then the correction factor for that band and the ambient.
lookup band = Table 90 row {conductors} column Band rule exact
cite Rule QR-12
lookup factor = Table 98 row {ambient} column Rating group {group} › {band} rule at_least
cite Rule QR-14
calc corrected (A) = load / factor
// The smallest rating at or above the corrected load gives the size.
lookup size = Table 99 column Rating group {group} cell {corrected} rule at_least
cite Rule QR-17
say "Use {size.row}: rated {size} A in rating group {group}, against {corrected} A once the load is divided by the factor of {factor} ({factor.table}, {factor.page})."
```

## Example: check an installed conductor
Answers: an invented example over made-up tables — whether a conductor already installed carries a load, after the same correction.

```chain
ask size (text): Which conductor is installed, by its designation and number of conductors?
ask load (A) range 1..400: What load does the circuit carry, in amps?
ask ambient (°C) range 0..40: What is the ambient temperature along the run?
ask conductors (conductors) range 1..9: How many current-carrying conductors share the run?
ask group range 1..3: Which rating group is the installation method in?
lookup band = Table 90 row {conductors} column Band rule exact
cite Rule QR-12
lookup factor = Table 98 row {ambient} column Rating group {group} › {band} rule at_least
cite Rule QR-14
// The installed conductor's own row, by its designation as said.
lookup rating = Table 99 row {size} column Rating group {group} rule exact
cite Rule QR-17
calc capacity (A) = rating * factor
check capacity >= load ? "{rating.row} carries it: {capacity} A once corrected, against a load of {load} A." : "{rating.row} does not carry it: {capacity} A once corrected, against a load of {load} A. The next row is {rating.next}."
```

## Example: voltage drop on a run
Answers: an invented example over a made-up table — the voltage drop along a run as a share of the supply, against the limit this example sets.

```chain
ask size (text): Which size is the run, as the table prints it?
ask current (A) range 1..400: What current does the run carry, in amps?
ask length (ft) range 1..2000: How long is the run, one way, in feet?
convert metres = length to m
// Table 97 here prints a drop per amp per 100 m; a table of resistances would use the voltage-drop expression above.
lookup drop = Table 97 row {size} column Drop rule exact
cite Rule QR-30
calc volts (V) = drop * current * metres / 100
ask supply (V) range 50..1000: What is the supply voltage?
calc percent (%) = volts / supply * 100
// The limit is the example's own; your chain cites the rule that sets yours.
check percent <= 4.5 ? "The drop is {volts} V, {percent} % of {supply} V: within the 4.5 % this example allows." : "The drop is {volts} V, {percent} % of {supply} V: over the 4.5 % this example allows, so a larger size or a shorter run is needed."
```
