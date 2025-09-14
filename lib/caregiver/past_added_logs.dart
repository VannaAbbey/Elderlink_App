import 'package:flutter/material.dart';

class PastAddedLogsScreen extends StatelessWidget {
  const PastAddedLogsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Color(0xFF22688E), size: 32),
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Center(
                child: Text(
                  'Past Added Logs',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF22688E),
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.calendar_today, color: Color(0xFF22688E), size: 32),
              onPressed: () {
                // TODO: Implement calendar picker
              },
            ),
          ],
        ),
        toolbarHeight: 80,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/background1.png',
              fit: BoxFit.cover,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),
                // TODO: Replace with backend data integration in the future
                // Card for past log (placeholder data)
                Card(
                  color: Color(0xFFE8F0FE),
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'May 27, 2025',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'I would like to add that Lola Andrea wanted to try more dancing exercises in the afternoon...',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.black,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Additional placeholder cards here...
              ],
            ),
          ),
        ],
      ),
    );
  }
}
