/// [ThemeRegistry]: the ChangeNotifier store behind the theme switchers.
///
/// Holds the catalog of [BoardTheme]s and [PieceTheme]s (built-ins plus user
/// customs) and the currently active selections. Screens mutate it through
/// the validated methods below; widgets rebuild via
/// [themeRegistryProvider] (a `ChangeNotifierProvider`, so no codegen is
/// needed). The app brightness switch lives here too as [themeModeProvider]
/// so settings and the app root share one source of truth.
///
/// Validation rules for custom themes (enforced by [addCustomBoardTheme] and
/// [addCustomPieceTheme]):
///
/// * `id` must be non-empty, lowercase alphanumerics/dashes/underscores, and
///   unique across built-ins *and* customs (built-ins cannot be shadowed).
/// * `name` must be non-blank.
/// * Removing ([removeCustomBoardTheme]/[removeCustomPieceTheme]) only works
///   for custom ids; built-ins are permanent. If the active theme is removed,
///   the registry falls back to the first built-in.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'board_theme.dart';
import 'piece_theme.dart';

/// Allowed shape for theme ids: lowercase letters, digits, `-` and `_`.
final RegExp _idPattern = RegExp(r'^[a-z0-9][a-z0-9_-]*$');

/// ChangeNotifier store for board/piece themes plus the active selections.
///
/// Construct with no arguments for the default (classic + meridian) setup.
class ThemeRegistry extends ChangeNotifier {
  /// Creates a registry, optionally pre-selecting themes by id.
  ///
  /// Unknown ids silently fall back to the first built-in.
  ThemeRegistry({
    String boardThemeId = 'classic',
    String pieceThemeId = 'meridian',
  }) {
    _boardId = BoardTheme.byId(boardThemeId).id;
    _pieceId = PieceTheme.byId(pieceThemeId).id;
  }

  final List<BoardTheme> _boardThemes = List<BoardTheme>.of(
    BoardTheme.builtins,
  );
  final List<PieceTheme> _pieceThemes = List<PieceTheme>.of(
    PieceTheme.builtins,
  );

  late String _boardId;
  late String _pieceId;

  /// All known board themes (built-ins first, then customs), unmodifiable.
  List<BoardTheme> get boardThemes =>
      List<BoardTheme>.unmodifiable(_boardThemes);

  /// All known piece themes (built-ins first, then customs), unmodifiable.
  List<PieceTheme> get pieceThemes =>
      List<PieceTheme>.unmodifiable(_pieceThemes);

  /// The currently active board theme.
  BoardTheme get boardTheme => _boardThemes.firstWhere(
    (t) => t.id == _boardId,
    orElse: () => BoardTheme.classic,
  );

  /// The currently active piece theme.
  PieceTheme get pieceTheme => _pieceThemes.firstWhere(
    (t) => t.id == _pieceId,
    orElse: () => PieceTheme.meridian,
  );

  /// `true` when [id] belongs to a built-in board theme.
  bool isBuiltInBoard(String id) => BoardTheme.builtins.any((t) => t.id == id);

  /// `true` when [id] belongs to a built-in piece theme.
  bool isBuiltInPiece(String id) => PieceTheme.builtins.any((t) => t.id == id);

  /// Activates the board theme [id]. Unknown ids are ignored.
  void useBoardTheme(String id) {
    if (_boardThemes.any((t) => t.id == id) && id != _boardId) {
      _boardId = id;
      notifyListeners();
    }
  }

  /// Activates the piece theme [id]. Unknown ids are ignored.
  void usePieceTheme(String id) {
    if (_pieceThemes.any((t) => t.id == id) && id != _pieceId) {
      _pieceId = id;
      notifyListeners();
    }
  }

  /// Validates and registers a custom board theme, then activates it.
  ///
  /// Throws [ArgumentError] when the id is malformed, blank-named, or
  /// already taken (including by a built-in).
  void addCustomBoardTheme(BoardTheme theme) {
    _validateNewId(theme.id, theme.name, _boardThemes.map((t) => t.id));
    _boardThemes.add(theme);
    _boardId = theme.id;
    notifyListeners();
  }

  /// Validates and registers a custom piece theme, then activates it.
  ///
  /// Throws [ArgumentError] under the same conditions as
  /// [addCustomBoardTheme].
  void addCustomPieceTheme(PieceTheme theme) {
    _validateNewId(theme.id, theme.name, _pieceThemes.map((t) => t.id));
    _pieceThemes.add(theme);
    _pieceId = theme.id;
    notifyListeners();
  }

  /// Removes a custom board theme. Returns `true` when something was removed.
  ///
  /// Built-ins are never removed (returns `false`). Removing the active
  /// theme falls back to [BoardTheme.classic].
  bool removeCustomBoardTheme(String id) {
    if (isBuiltInBoard(id)) return false;
    final index = _boardThemes.indexWhere((t) => t.id == id);
    if (index < 0) return false;
    _boardThemes.removeAt(index);
    if (_boardId == id) _boardId = BoardTheme.classic.id;
    notifyListeners();
    return true;
  }

  /// Removes a custom piece theme. Returns `true` when something was removed.
  ///
  /// Built-ins are never removed (returns `false`). Removing the active
  /// theme falls back to [PieceTheme.meridian].
  bool removeCustomPieceTheme(String id) {
    if (isBuiltInPiece(id)) return false;
    final index = _pieceThemes.indexWhere((t) => t.id == id);
    if (index < 0) return false;
    _pieceThemes.removeAt(index);
    if (_pieceId == id) _pieceId = PieceTheme.meridian.id;
    notifyListeners();
    return true;
  }

  /// Shared id/name validation for custom themes.
  void _validateNewId(String id, String name, Iterable<String> taken) {
    if (!_idPattern.hasMatch(id)) {
      throw ArgumentError.value(
        id,
        'id',
        'must be lowercase alphanumerics, dashes or underscores',
      );
    }
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'must be non-blank');
    }
    if (taken.contains(id)) {
      throw ArgumentError.value(id, 'id', 'is already taken');
    }
  }
}

/// Riverpod provider for the shared [ThemeRegistry].
///
/// Declared next to the store (instead of in `app.dart`) so settings and
/// board widgets can consume it without import cycles; `app.dart`
/// re-exports it as part of the app's provider surface.
final ChangeNotifierProvider<ThemeRegistry> themeRegistryProvider =
    ChangeNotifierProvider<ThemeRegistry>((ref) => ThemeRegistry());

/// Riverpod provider for the app [ThemeMode] (light/dark/system).
///
/// Kept beside the theme registry because the settings screen toggles both
/// together. Update via `ref.read(themeModeProvider.notifier).state = …`.
final StateProvider<ThemeMode> themeModeProvider = StateProvider<ThemeMode>(
  (ref) => ThemeMode.system,
);
