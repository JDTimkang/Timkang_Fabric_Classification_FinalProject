import 'package:flutter/material.dart';
import '../../app_theme.dart';
import '../../core/services/fabric_classifier_service.dart';

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  final _classifier = FabricClassifierService.instance;
  bool _isRunning = false;
  final List<_DemoResult> _results = [];

  Future<void> _runDemo() async {
    setState(() {
      _isRunning = true;
      _results.clear();
    });

    // Use the existing fabric images as demo inputs
    for (final name in AppColors.classNames) {
      final assetPath = 'assets/images/$name.png';
      final result = await _classifier.classifyAsset(assetPath);

      _results.add(_DemoResult(
        fabricName: name,
        assetPath: assetPath,
        result: result,
      ));

      if (!mounted) return;
      setState(() {});
    }

    setState(() => _isRunning = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Demo Mode'),
        backgroundColor: Theme.of(context).cardColor,
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            const Text(
              'Demo Mode: run classifier on bundled fabric images.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton(
                  onPressed: _isRunning ? null : _runDemo,
                  child: _isRunning
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Run Demo'),
                ),
                const SizedBox(width: 12),
                const Text('Runs classification for each asset image'),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: _results.length,
                itemBuilder: (context, index) {
                  final r = _results[index];
                  final label = r.result == null
                      ? 'Error'
                      : _classifier.cleanLabel(r.result!.topLabel);
                  final confidence = r.result == null
                      ? 0
                      : (r.result!.topConfidence * 100).toStringAsFixed(2);

                  return Card(
                    child: ListTile(
                      leading: Image.asset(
                        r.assetPath,
                        width: 48,
                        height: 48,
                        fit: BoxFit.contain,
                      ),
                      title: Text(r.fabricName),
                      subtitle: Text('Predicted: $label'),
                      trailing: Text('$confidence%'),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DemoResult {
  final String fabricName;
  final String assetPath;
  final dynamic result; // ClassificationResult? (keeps import simple for tests)

  _DemoResult({
    required this.fabricName,
    required this.assetPath,
    required this.result,
  });
}
