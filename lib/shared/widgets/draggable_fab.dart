import 'package:flutter/material.dart';

/// A compact circular action button whose position can be adjusted within the
/// available stack. Position is intentionally session-local and clamped so it
/// remains reachable above the navigation/system areas.
class DraggableFab extends StatefulWidget {
  const DraggableFab({super.key, required this.onPressed, this.tooltip = '添加'});

  final VoidCallback onPressed;
  final String tooltip;

  @override
  State<DraggableFab> createState() => _DraggableFabState();
}

class _DraggableFabState extends State<DraggableFab> {
  Offset _position = const Offset(20, 20);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const size = 56.0;
        final maxX = (constraints.maxWidth - size - 8).clamp(
          8.0,
          double.infinity,
        );
        final maxY = (constraints.maxHeight - size - 8).clamp(
          8.0,
          double.infinity,
        );
        final left = _position.dx.clamp(8.0, maxX);
        final bottom = _position.dy.clamp(8.0, maxY);
        return Align(
          alignment: Alignment.bottomRight,
          child: Transform.translate(
            offset: Offset(-left, -bottom),
            child: GestureDetector(
              onPanUpdate: (details) => setState(() {
                _position = Offset(
                  (left - details.delta.dx).clamp(8.0, maxX),
                  (bottom - details.delta.dy).clamp(8.0, maxY),
                );
              }),
              child: FloatingActionButton(
                heroTag: widget.key,
                tooltip: widget.tooltip,
                onPressed: widget.onPressed,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Icon(Icons.add),
                    Opacity(opacity: 0, child: Text(widget.tooltip)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
