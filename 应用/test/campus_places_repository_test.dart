import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/core/models/app_models.dart';
import 'package:research_life/services/database/app_database.dart'
    hide CampusPlace;
import 'package:research_life/services/database/repositories/campus_places_repository.dart';

void main() {
  late AppDatabase database;
  late CampusPlacesRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = CampusPlacesRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('saves and loads campus places', () async {
    final place = _buildCampusPlace();

    await repository.saveCampusPlace(place);
    final loaded = await repository.loadCampusPlaces();

    expect(loaded, hasLength(1));
    expect(loaded.single.id, place.id);
    expect(loaded.single.name, place.name);
    expect(loaded.single.category, place.category);
    expect(loaded.single.isFavorite, isTrue);
    expect(loaded.single.heatScore, 3);
  });

  test('deletes campus place by id', () async {
    final place = _buildCampusPlace();
    await repository.saveCampusPlace(place);

    await repository.deleteCampusPlace(place.id);

    expect(await repository.loadCampusPlaces(), isEmpty);
  });

  test('tracks default seeding flag', () async {
    expect(await repository.hasSeededDefaults(), isFalse);

    await repository.markSeededDefaults();

    expect(await repository.hasSeededDefaults(), isTrue);
  });
}

CampusPlace _buildCampusPlace() {
  final now = DateTime(2026, 4, 26, 10);
  return CampusPlace(
    id: 'place_1',
    name: 'Library',
    category: PlaceCategory.study,
    note: 'Quiet study area',
    normalizedDx: 0.4,
    normalizedDy: 0.5,
    iconKey: 'book',
    colorKey: 'forest',
    isFavorite: true,
    createdAt: now,
    updatedAt: now,
    lastVisitedAt: now,
    heatScore: 3,
  );
}
