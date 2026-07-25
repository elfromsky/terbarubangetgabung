class EstimateEmissionUseCase {
  final double emissionFactorKgCo2PerKwh;

  const EstimateEmissionUseCase({required this.emissionFactorKgCo2PerKwh});

  double call({required double energyKwh}) {
    return energyKwh * emissionFactorKgCo2PerKwh;
  }
}
