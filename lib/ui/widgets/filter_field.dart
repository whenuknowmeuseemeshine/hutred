import 'package:flutter/material.dart';

import '../../models/track.dart';

/// Подходит ли трек под поиск: все слова есть в названии, исполнителе или альбоме.
bool trackMatches(Track t, String query) {
  final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  if (words.isEmpty) return true;
  final hay = '${t.title} ${t.artist} ${t.album}'.toLowerCase();
  return words.every(hay.contains);
}

/// Небольшое поле поиска внутри медиатеки и плейлиста.
class FilterField extends StatefulWidget {
  const FilterField({super.key, required this.onChanged, this.hint = 'Найти трек', this.width});
  final ValueChanged<String> onChanged;
  final String hint;
  final double? width;

  @override
  State<FilterField> createState() => _FilterFieldState();
}

class _FilterFieldState extends State<FilterField> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: 40,
      child: TextField(
        controller: _c,
        onChanged: (v) {
          setState(() {});
          widget.onChanged(v);
        },
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          isDense: true,
          hintText: widget.hint,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          suffixIcon: _c.text.isEmpty
              ? null
              : IconButton(
                  iconSize: 18,
                  onPressed: () {
                    _c.clear();
                    setState(() {});
                    widget.onChanged('');
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: Colors.white38),
          ),
        ),
      ),
    );
  }
}
