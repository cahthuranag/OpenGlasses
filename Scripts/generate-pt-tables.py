#!/usr/bin/env python3
"""Generate the bundled refrigerant saturation (P-T) tables from CoolProp (Plan IS P0).

Run by hand, never in CI. The output is committed:
OpenGlasses/Sources/Resources/Refrigerants/<designation>.json, one file per refrigerant.

Each file holds two temperature grids, each computed directly by CoolProp (neither is converted
from the other):

  fahrenheit: -40 F to 150 F in 1 F steps
  celsius:    -40 C to 65 C in 0.5 C steps

and for each grid a `dew` and a `bubble` series of saturation pressures, stored ABSOLUTE in kPa
to 0.01 kPa. There is no gauge column: the app derives gauge pressure at read time from the local
atmosphere (sea level by default). A refrigerant whose critical point lies inside the grid (R-744)
stops at the last grid point below it, and the file records the critical point.

CoolProp is pinned to an exact version. Set the environment up outside the repository:

  python3 -m venv ~/Library/Caches/og-is-coolprop-venv
  ~/Library/Caches/og-is-coolprop-venv/bin/pip install --index-url https://pypi.org/simple \
      "CoolProp==8.0.0"
  ~/Library/Caches/og-is-coolprop-venv/bin/python -I Scripts/generate-pt-tables.py

`--check-points` prints, instead of writing files, the CoolProp reference values the unit tests
embed (SaturationTableCoolPropReferenceTests): a dozen off-grid and on-grid temperatures per
refrigerant, at full precision.

Blends CoolProp does not define are not generated here. Decision 1: one is added only from a
cited manufacturer table, never from anyone's chart copied by hand.
"""

import argparse
import json
import math
import os
import sys

PINNED_COOLPROP = "8.0.0"

try:
    import CoolProp
    import CoolProp.CoolProp as CP
except ImportError:  # pragma: no cover - environment check
    sys.exit(f"CoolProp is not installed. Install CoolProp=={PINNED_COOLPROP} in a venv (see the header).")

if CoolProp.__version__ != PINNED_COOLPROP:
    sys.exit(f"CoolProp {CoolProp.__version__} is installed; this script is pinned to {PINNED_COOLPROP}.")

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(REPO, "OpenGlasses", "Sources", "Resources", "Refrigerants")

# (designation, CoolProp fluid string, model)
#   pure        - a pure-fluid equation of state
#   pseudo-pure - Lemmon's pseudo-pure blend model (separate bubble and dew curves)
#   mixture     - CoolProp's predefined blend, solved as a real mixture (HEOS)
REFRIGERANTS = [
    ("R-22", "R22", "pure"),
    ("R-32", "R32", "pure"),
    ("R-134a", "R134a", "pure"),
    ("R-404A", "R404A", "pseudo-pure"),
    ("R-407A", "HEOS::R407A.mix", "mixture"),
    ("R-407C", "R407C", "pseudo-pure"),
    ("R-410A", "R410A", "pseudo-pure"),
    ("R-454B", "HEOS::R454B.mix", "mixture"),
    ("R-507A", "R507A", "pseudo-pure"),
    ("R-290", "R290", "pure"),
    ("R-600a", "R600a", "pure"),
    ("R-744", "R744", "pure"),
    ("R-1234yf", "R1234yf", "pure"),
]

GRIDS = {
    "fahrenheit": {"start": -40.0, "end": 150.0, "step": 1.0},
    "celsius": {"start": -40.0, "end": 65.0, "step": 0.5},
}

# Off-grid and on-grid check temperatures for the reference test (12 per refrigerant).
CHECK_POINTS = [
    ("fahrenheit", -37.3), ("fahrenheit", 0.0), ("fahrenheit", 12.6), ("fahrenheit", 25.25),
    ("fahrenheit", 40.0), ("fahrenheit", 47.7), ("fahrenheit", 66.4), ("fahrenheit", 85.5),
    ("celsius", -21.3), ("celsius", 4.75), ("celsius", 18.2), ("celsius", 27.9),
]

SOURCE = (
    "Generated with CoolProp {version} (git {revision}). Bell, I. H.; Wronski, J.; Quoilin, S.; "
    "Lemort, V. Pure and Pseudo-pure Fluid Thermophysical Property Evaluation and the Open-Source "
    "Thermophysical Property Library CoolProp. Ind. Eng. Chem. Res. 2014, 53 (6), 2498-2508."
)
LICENCE = "CoolProp is MIT licensed. Copyright (c) 2012-2018 Ian H. Bell and other CoolProp developers."


def kelvin(unit, t):
    return (t + 459.67) / 1.8 if unit == "fahrenheit" else t + 273.15


def critical_point(fluid):
    """(T in K, p in kPa). A predefined mixture that PropsSI cannot answer is solved by AbstractState."""
    try:
        return CP.PropsSI("Tcrit", fluid), CP.PropsSI("pcrit", fluid) / 1000.0
    except ValueError:
        state = CP.AbstractState("HEOS", fluid.split("::", 1)[1])
        stable = [point for point in state.all_critical_points() if point.stable and point.p > 0]
        if len(stable) != 1:
            sys.exit(f"{fluid}: expected one stable critical point, found {len(stable)}")
        return stable[0].T, stable[0].p / 1000.0


FALLBACKS = []  # (fluid, T K, quality) solved by continuation, reported at the end


class Saturation:
    """Saturation pressure (kPa abs) at T for one fluid.

    Pure and pseudo-pure fluids go straight to PropsSI. A predefined mixture is solved as a real
    vapour-liquid equilibrium; CoolProp's (T, Q) mixture solver occasionally fails to converge from its
    own starting point at higher temperatures, and then the same equilibrium is solved again starting
    from the neighbouring converged state (update_with_guesses: pressure, phase densities and phase
    compositions). The equations are unchanged; only the solver's starting point differs, and every
    series is checked for smoothness afterwards.
    """

    def __init__(self, fluid):
        self.fluid = fluid
        self.mixture = "::" in fluid
        self.state = CP.AbstractState("HEOS", fluid.split("::", 1)[1]) if self.mixture else None
        self.previous = {0.0: None, 1.0: None}

    def kpa(self, t_k, quality):
        if not self.mixture:
            return CP.PropsSI("P", "T", t_k, "Q", quality, self.fluid) / 1000.0
        try:
            self.state.update(CP.QT_INPUTS, quality, t_k)
        except ValueError:
            guess = self.previous[quality]
            if guess is None or abs(guess.T - t_k) > 1.0:
                guess = self._march_to(t_k, quality)
            FALLBACKS.append((self.fluid, t_k, quality))
            self.state.update_with_guesses(CP.QT_INPUTS, quality, t_k, guess)
        self.previous[quality] = self._snapshot(t_k)
        return self.state.p() / 1000.0

    def _snapshot(self, t_k):
        guess = CP.PyGuessesStructure()
        guess.T = t_k
        guess.p = self.state.p()
        guess.rhomolar_liq = self.state.saturated_liquid_keyed_output(CP.iDmolar)
        guess.rhomolar_vap = self.state.saturated_vapor_keyed_output(CP.iDmolar)
        guess.x = self.state.mole_fractions_liquid()
        guess.y = self.state.mole_fractions_vapor()
        return guess

    def _march_to(self, t_k, quality):
        """Walk up to t_k from 10 K below in 0.25 K steps, carrying the converged state forward."""
        guess = None
        for i in range(40):
            t = t_k - 10.0 + 0.25 * i
            try:
                self.state.update(CP.QT_INPUTS, quality, t)
            except ValueError:
                if guess is None:
                    sys.exit(f"{self.fluid}: no converged state below T={t_k} K (Q={quality})")
                self.state.update_with_guesses(CP.QT_INPUTS, quality, t, guess)
            guess = self._snapshot(t)
        return guess


def grid_temperatures(spec):
    count = int(round((spec["end"] - spec["start"]) / spec["step"])) + 1
    return [spec["start"] + i * spec["step"] for i in range(count)]


def equation_of_state(fluid, model):
    if model != "mixture":
        return CP.get_fluid_param_string(fluid, "BibTeX-EOS")
    state = CP.AbstractState("HEOS", fluid.split("::", 1)[1])
    names = state.fluid_names()
    fractions = state.get_mole_fractions()
    parts = [f"{name} {fraction:.4f}" for name, fraction in zip(names, fractions)]
    keys = [CP.get_fluid_param_string(name, "BibTeX-EOS") for name in names]
    return "HEOS mixture, mole fractions " + ", ".join(parts) + "; component EOS " + ", ".join(keys)


def series(fluid, unit, spec, t_crit_k):
    solver = Saturation(fluid)
    dew, bubble = [], []
    end = spec["start"]
    for t in grid_temperatures(spec):
        t_k = kelvin(unit, t)
        if t_k >= t_crit_k:
            break
        d = solver.kpa(t_k, 1.0)
        b = solver.kpa(t_k, 0.0)
        if not (math.isfinite(d) and math.isfinite(b)) or d <= 0 or b <= 0:
            sys.exit(f"{fluid}: no saturation pressure at {t} ({unit})")
        dew.append(d)
        bubble.append(b)
        end = t
    for name, values in (("dew", dew), ("bubble", bubble)):
        if any(later <= earlier for earlier, later in zip(values, values[1:])):
            sys.exit(f"{fluid}: {name} series is not strictly increasing ({unit})")
        check_smooth(fluid, unit, name, values)
    return {"start": spec["start"], "end": end, "step": spec["step"],
            "dew": [round(v, 2) for v in dew], "bubble": [round(v, 2) for v in bubble]}


def check_smooth(fluid, unit, name, values):
    """Each interior point must sit on the curve through its four neighbours (ln p, cubic), to 2e-5.
    A solver that converged to the wrong root shows up here."""
    logs = [math.log(v) for v in values]
    for i in range(2, len(logs) - 2):
        predicted = (-logs[i - 2] + 4 * logs[i - 1] + 4 * logs[i + 1] - logs[i + 2]) / 6.0
        if abs(predicted - logs[i]) > 2e-5:
            sys.exit(f"{fluid}: {name} point {i} ({unit}) is off the curve by {abs(predicted - logs[i]):.2e}")


def table(designation, fluid, model):
    t_crit_k, p_crit_kpa = critical_point(fluid)
    fahrenheit = series(fluid, "fahrenheit", GRIDS["fahrenheit"], t_crit_k)
    celsius = series(fluid, "celsius", GRIDS["celsius"], t_crit_k)
    full = GRIDS["fahrenheit"]["end"] == fahrenheit["end"] and GRIDS["celsius"]["end"] == celsius["end"]
    if not full and designation != "R-744":
        sys.exit(f"{designation}: the grid stops short of its end; only R-744 may stop at the critical point")
    return {
        "designation": designation,
        "coolPropFluid": fluid,
        "model": model,
        "equationOfState": equation_of_state(fluid, model),
        "pressureUnit": "kPa absolute",
        "criticalTemperatureK": round(t_crit_k, 3),
        "criticalPressureKPa": round(p_crit_kpa, 2),
        "fahrenheit": fahrenheit,
        "celsius": celsius,
        "source": SOURCE.format(version=CoolProp.__version__, revision=CoolProp.__gitrevision__),
        "licence": LICENCE,
        "generatedWith": "Scripts/generate-pt-tables.py",
        "libraryVersion": CoolProp.__version__,
    }


def write_tables():
    os.makedirs(OUT_DIR, exist_ok=True)
    for designation, fluid, model in REFRIGERANTS:
        data = table(designation, fluid, model)
        path = os.path.join(OUT_DIR, f"{designation}.json")
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(data, handle, sort_keys=True, separators=(",", ":"), ensure_ascii=True)
            handle.write("\n")
        print(f"{designation}: {len(data['fahrenheit']['dew'])} F points to {data['fahrenheit']['end']} F, "
              f"{len(data['celsius']['dew'])} C points to {data['celsius']['end']} C -> {os.path.relpath(path, REPO)}")


def report_fallbacks():
    if FALLBACKS:
        print(f"{len(FALLBACKS)} mixture points solved by continuation from the neighbouring state:")
        for fluid, t_k, quality in FALLBACKS:
            print(f"  {fluid} T={t_k:.4f} K Q={quality:g}")


def print_check_points():
    print(f"// CoolProp {CoolProp.__version__} (git {CoolProp.__gitrevision__}), "
          "printed by Scripts/generate-pt-tables.py --check-points")
    print("// (designation, unit, temperature, dew kPa abs, bubble kPa abs)")
    for designation, fluid, _ in REFRIGERANTS:
        t_crit_k, _ = critical_point(fluid)
        for unit, t in CHECK_POINTS:
            t_k = kelvin(unit, t)
            if t_k >= t_crit_k:
                continue
            solver = Saturation(fluid)
            d = solver.kpa(t_k, 1.0)
            b = solver.kpa(t_k, 0.0)
            u = ".fahrenheit" if unit == "fahrenheit" else ".celsius"
            print(f'    ("{designation}", {u}, {t}, {d:.4f}, {b:.4f}),')


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("--check-points", action="store_true",
                        help="print the CoolProp reference values for the unit tests instead of writing files")
    args = parser.parse_args()
    if args.check_points:
        print_check_points()
    else:
        write_tables()
    report_fallbacks()


if __name__ == "__main__":
    main()
