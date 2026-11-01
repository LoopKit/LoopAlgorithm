# LoopAlgorithm

![Platform](https://img.shields.io/badge/platforms-iOS%2015.0%20%7C%20macOS%2013.0%20%7C%20tvOS%2015.0%20%7C%20watchOS%208.0-F28D00.svg)

LoopAlgorithm predicts future blood glucose from insulin, carb, and historic glucose data, and generates dosing recommendations. 

Please understand that this project:

* Is highly experimental
* Is not approved for therapy

## Usage

The entry point is `Algorithm.run(input:)`, which takes any type conforming to `AlgorithmInput` and returns the
glucose forecast, the effects behind it, and a dose recommendation. The API takes plain numbers in fixed units:

| Quantity | Unit |
|---|---|
| Glucose, targets, suspend threshold | mg/dL |
| Insulin sensitivity | mg/dL per unit |
| Carbs | grams |
| Carb ratio | grams per unit |
| Insulin | units |
| Basal rates | U/h |

Apps that store values in other units (mmol/L) convert before calling. `Algorithm.generatePrediction` produces a
forecast without a recommendation.

## Command Line Runner

There is a command line utility that will run the algorithm with a scenario input file:

```
swift build
./.build/debug/LoopAlgorithmRunner Tests/LoopAlgorithmTests/Fixtures/suspend_scenario.json > output.json
```
