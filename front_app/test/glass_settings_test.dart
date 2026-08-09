import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/core/models/app_models.dart';

void main() {
  group('GlassSettings', () {
    test('round trips through json', () {
      const settings = GlassSettings(
        blurSigma: 32,
        opacity: 0.72,
        noiseEnabled: false,
        highlightEnabled: true,
      );

      final restored = GlassSettings.fromJson(settings.toJson());

      expect(restored.blurSigma, 32);
      expect(restored.opacity, 0.72);
      expect(restored.noiseEnabled, isFalse);
      expect(restored.highlightEnabled, isTrue);
    });

    test('uses defaults for empty json', () {
      final restored = GlassSettings.fromJson(const {});

      expect(restored.blurSigma, GlassSettings.defaultBlurSigma);
      expect(restored.opacity, GlassSettings.defaultOpacity);
      expect(restored.noiseEnabled, isTrue);
      expect(restored.highlightEnabled, isTrue);
    });

    test('clamps out-of-range numeric values on load', () {
      final restored = GlassSettings.fromJson(const {
        'blurSigma': 999,
        'opacity': -1,
      });

      expect(restored.blurSigma, GlassSettings.maxBlurSigma);
      expect(restored.opacity, GlassSettings.minOpacity);
    });

    test('falls back to defaults for garbage input', () {
      final restored = GlassSettings.fromJson(const {
        'blurSigma': 'not-a-number',
        'opacity': null,
      });

      expect(restored.blurSigma, GlassSettings.defaultBlurSigma);
      expect(restored.opacity, GlassSettings.defaultOpacity);
    });

    test('copyWith keeps unspecified fields', () {
      const settings = GlassSettings(blurSigma: 18, opacity: 0.55);
      final updated = settings.copyWith(noiseEnabled: false);

      expect(updated.blurSigma, 18);
      expect(updated.opacity, 0.55);
      expect(updated.noiseEnabled, isFalse);
      expect(updated.highlightEnabled, isTrue);
    });
  });
}
