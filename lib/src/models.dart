class FatxSearchResult {
  final int gameCluster;
  final int? saveCluster;
  final String gameName;
  final String? saveName;

  FatxSearchResult({
    required this.gameCluster,
    this.saveCluster,
    required this.gameName,
    this.saveName,
  });
}
