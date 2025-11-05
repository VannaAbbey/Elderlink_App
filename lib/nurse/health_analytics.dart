import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';

class HealthAnalyticsScreen extends StatefulWidget {
  final String houseId;
  final String? nurseName;

  const HealthAnalyticsScreen({
    super.key,
    required this.houseId,
    this.nurseName,
  });

  @override
  State<HealthAnalyticsScreen> createState() => _HealthAnalyticsScreenState();
}

class _HealthAnalyticsScreenState extends State<HealthAnalyticsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = true;
  List<Map<String, dynamic>> _elderlyHealthData = [];
  final Map<String, List<Map<String, dynamic>>> _vitalsHistory = {};
  Map<String, String> _healthStatus = {};

  @override
  void initState() {
    super.initState();
    _loadHealthAnalytics();
  }

  Future<void> _loadHealthAnalytics() async {
    setState(() => _isLoading = true);

    try {
      await _loadElderlyHealthData();
      await _analyzeHealthTrends();
      await _identifyCriticalCases();
    } catch (e) {
      print('Error loading health analytics: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadElderlyHealthData() async {
    try {
      // Get all elderly in the current house
      final elderlyQuery = await _firestore
          .collection('elderly')
          .where('house_id', isEqualTo: widget.houseId)
          .where('elderly_status', isEqualTo: 'Alive')
          .get();

      final elderlyData = <Map<String, dynamic>>[];

      for (final elderlyDoc in elderlyQuery.docs) {
        final elderly = elderlyDoc.data();
        final elderlyId = elderlyDoc.id;

        // Get recent vitals for this elderly (last 30 days)
        final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
        final vitalsQuery = await _firestore
            .collection('vitals')
            .where('elderly_id', isEqualTo: elderlyId)
            .where('status', isEqualTo: 'completed')
            .where(
              'completed_at',
              isGreaterThan: Timestamp.fromDate(thirtyDaysAgo),
            )
            .orderBy('completed_at', descending: true)
            .limit(20)
            .get();

        final vitals = vitalsQuery.docs
            .map((doc) => {...doc.data(), 'vital_id': doc.id})
            .toList();

        if (vitals.isNotEmpty) {
          // Calculate health metrics
          final latestVital = vitals.first;
          final healthScore = _calculateHealthScore(latestVital);
          final trend = _calculateShortTermTrend(vitals);

          elderlyData.add({
            'elderly_id': elderlyId,
            'name':
                '${elderly['elderly_fname'] ?? ''} ${elderly['elderly_lname'] ?? ''}'
                    .trim(),
            'age': _calculateAge(elderly['elderly_birthdate']),
            'latest_vitals': latestVital,
            'vitals_history': vitals,
            'health_score': healthScore,
            'trend': trend,
            'critical_flags': _getCriticalFlags(latestVital),
          });

          _vitalsHistory[elderlyId] = vitals;
        }
      }

      // Sort by health score (worst first) and then by critical flags
      elderlyData.sort((a, b) {
        final aCritical = (a['critical_flags'] as List).isNotEmpty ? 1 : 0;
        final bCritical = (b['critical_flags'] as List).isNotEmpty ? 1 : 0;

        if (aCritical != bCritical) return bCritical - aCritical;

        return (a['health_score'] as double).compareTo(
          b['health_score'] as double,
        );
      });

      setState(() => _elderlyHealthData = elderlyData);
    } catch (e) {
      print('Error loading elderly health data: $e');
    }
  }

  Future<void> _analyzeHealthTrends() async {
    final statusUpdates = <String, String>{};

    for (final elderly in _elderlyHealthData) {
      final elderlyId = elderly['elderly_id'];
      final vitals = _vitalsHistory[elderlyId] ?? [];

      if (vitals.length >= 3) {
        final trend = _calculateLongTermTrend(vitals);
        final healthScore = elderly['health_score'] as double;

        String status;
        if (healthScore < 50) {
          status = 'Critical';
        } else if (trend == 'declining') {
          status = 'Declining';
        } else if (trend == 'improving') {
          status = 'Improving';
        } else {
          status = 'Stable';
        }

        statusUpdates[elderlyId] = status;
      } else {
        statusUpdates[elderlyId] = 'Monitoring';
      }
    }

    setState(() => _healthStatus = statusUpdates);
  }

  Future<void> _identifyCriticalCases() async {
    // This could be enhanced with more sophisticated critical condition detection
    // For now, we'll use the existing critical flags
  }

  double _calculateHealthScore(Map<String, dynamic> vitals) {
    double score = 100.0;

    // Blood Pressure (target: 120/80)
    final bp = vitals['blood_pressure']?.toString() ?? '';
    if (bp.isNotEmpty) {
      final parts = bp.split('/');
      if (parts.length == 2) {
        final systolic = double.tryParse(parts[0]) ?? 120;
        final diastolic = double.tryParse(parts[1]) ?? 80;

        if (systolic > 140 ||
            systolic < 90 ||
            diastolic > 90 ||
            diastolic < 60) {
          score -= 20;
        }
      }
    }

    // Pulse Rate (target: 60-100)
    final pulse = double.tryParse(vitals['pulse_rate']?.toString() ?? '') ?? 75;
    if (pulse < 60 || pulse > 100) {
      score -= 15;
    }

    // Oxygen Saturation (target: >95%)
    final o2 =
        double.tryParse(vitals['oxygen_saturation']?.toString() ?? '') ?? 98;
    if (o2 < 95) {
      score -= 25;
    }

    // Temperature (target: 36.5-37.5°C)
    final temp =
        double.tryParse(vitals['temperature']?.toString() ?? '') ?? 37.0;
    if (temp < 36.5 || temp > 37.5) {
      score -= 15;
    }

    // Respiratory Rate (target: 12-20)
    final resp =
        double.tryParse(vitals['respiratory_rate']?.toString() ?? '') ?? 16;
    if (resp < 12 || resp > 20) {
      score -= 15;
    }

    return score.clamp(0.0, 100.0);
  }

  String _calculateShortTermTrend(List<Map<String, dynamic>> vitals) {
    if (vitals.length < 2) return 'stable';

    final recent = vitals.take(3).toList();
    final scores = recent.map((v) => _calculateHealthScore(v)).toList();

    final avgFirst = (scores[0] + scores[1]) / 2;
    final latest = scores[2];

    if (latest > avgFirst + 5) return 'improving';
    if (latest < avgFirst - 5) return 'declining';
    return 'stable';
  }

  String _calculateLongTermTrend(List<Map<String, dynamic>> vitals) {
    if (vitals.length < 5) return 'stable';

    final scores = vitals.take(7).map((v) => _calculateHealthScore(v)).toList();
    final firstHalf = scores.take((scores.length / 2).floor()).toList();
    final secondHalf = scores.skip((scores.length / 2).floor()).toList();

    final avgFirst = firstHalf.reduce((a, b) => a + b) / firstHalf.length;
    final avgSecond = secondHalf.reduce((a, b) => a + b) / secondHalf.length;

    if (avgSecond > avgFirst + 5) return 'improving';
    if (avgSecond < avgFirst - 5) return 'declining';
    return 'stable';
  }

  List<String> _getCriticalFlags(Map<String, dynamic> vitals) {
    final flags = <String>[];

    // Blood Pressure
    final bp = vitals['blood_pressure']?.toString() ?? '';
    if (bp.isNotEmpty) {
      final parts = bp.split('/');
      if (parts.length == 2) {
        final systolic = double.tryParse(parts[0]) ?? 120;
        final diastolic = double.tryParse(parts[1]) ?? 80;
        if (systolic > 180 ||
            systolic < 90 ||
            diastolic > 110 ||
            diastolic < 50) {
          flags.add('Critical Blood Pressure');
        }
      }
    }

    // Oxygen Saturation
    final o2 =
        double.tryParse(vitals['oxygen_saturation']?.toString() ?? '') ?? 98;
    if (o2 < 92) {
      flags.add('Low Oxygen Saturation');
    }

    // Temperature
    final temp =
        double.tryParse(vitals['temperature']?.toString() ?? '') ?? 37.0;
    if (temp > 38.5 || temp < 35.5) {
      flags.add('Abnormal Temperature');
    }

    return flags;
  }

  int _calculateAge(Timestamp? birthdate) {
    if (birthdate == null) return 0;
    final birth = birthdate.toDate();
    final now = DateTime.now();
    int age = now.year - birth.year;
    if (now.month < birth.month ||
        (now.month == birth.month && now.day < birth.day)) {
      age--;
    }
    return age;
  }

  Color _getHealthColor(String status) {
    switch (status) {
      case 'Critical':
        return Colors.red;
      case 'Declining':
        return Colors.orange;
      case 'Improving':
        return Colors.green;
      case 'Stable':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  Widget _buildHealthChart(
    String elderlyId,
    List<Map<String, dynamic>> vitals,
  ) {
    if (vitals.length < 2) {
      return const Center(
        child: Text(
          'Insufficient data for chart',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    final spots = <FlSpot>[];
    for (int i = 0; i < vitals.length && i < 10; i++) {
      final score = _calculateHealthScore(vitals[i]);
      spots.add(FlSpot(i.toDouble(), score));
    }

    return SizedBox(
      height: 150,
      child: LineChart(
        LineChartData(
          gridData: FlGridData(show: false),
          titlesData: FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: Colors.blue,
              barWidth: 3,
              belowBarData: BarAreaData(
                show: true,
                color: Colors.blue.withOpacity(0.1),
              ),
              dotData: FlDotData(show: true),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Health Analytics Dashboard'),
        backgroundColor: const Color(0xFF00588E),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadHealthAnalytics,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadHealthAnalytics,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Summary Cards
                    Row(
                      children: [
                        _buildSummaryCard(
                          'Total Patients',
                          _elderlyHealthData.length.toString(),
                          Icons.people,
                          Colors.blue,
                        ),
                        const SizedBox(width: 16),
                        _buildSummaryCard(
                          'Critical Cases',
                          _elderlyHealthData
                              .where(
                                (e) => (e['critical_flags'] as List).isNotEmpty,
                              )
                              .length
                              .toString(),
                          Icons.warning,
                          Colors.red,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _buildSummaryCard(
                          'Improving',
                          _healthStatus.values
                              .where((s) => s == 'Improving')
                              .length
                              .toString(),
                          Icons.trending_up,
                          Colors.green,
                        ),
                        const SizedBox(width: 16),
                        _buildSummaryCard(
                          'Declining',
                          _healthStatus.values
                              .where((s) => s == 'Declining')
                              .length
                              .toString(),
                          Icons.trending_down,
                          Colors.orange,
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),
                    const Text(
                      'Patient Health Overview',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF00588E),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Patient List
                    ..._elderlyHealthData.map(
                      (elderly) => _buildPatientCard(elderly),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSummaryCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Card(
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(icon, size: 32, color: color),
              const SizedBox(height: 8),
              Text(
                value,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                title,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPatientCard(Map<String, dynamic> elderly) {
    final status = _healthStatus[elderly['elderly_id']] ?? 'Monitoring';
    final criticalFlags = elderly['critical_flags'] as List<String>;
    final vitals = _vitalsHistory[elderly['elderly_id']] ?? [];

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 3,
      child: ExpansionTile(
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: _getHealthColor(status),
              child: Text(
                elderly['name'].toString().split(' ').map((n) => n[0]).join(''),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    elderly['name'],
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    'Age: ${elderly['age']} • Health Score: ${elderly['health_score'].toStringAsFixed(1)}',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _getHealthColor(status).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _getHealthColor(status)),
              ),
              child: Text(
                status,
                style: TextStyle(
                  color: _getHealthColor(status),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        subtitle: criticalFlags.isNotEmpty
            ? Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '⚠️ ${criticalFlags.join(", ")}',
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              )
            : null,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Health Trend (Last 10 Readings)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                _buildHealthChart(elderly['elderly_id'], vitals),
                const SizedBox(height: 16),
                const Text(
                  'Latest Vitals',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                _buildVitalsSummary(elderly['latest_vitals']),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVitalsSummary(Map<String, dynamic> vitals) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildVitalItem(
                'BP',
                vitals['blood_pressure'] ?? 'N/A',
                'mmHg',
              ),
            ),
            Expanded(
              child: _buildVitalItem(
                'Pulse',
                vitals['pulse_rate'] ?? 'N/A',
                'bpm',
              ),
            ),
            Expanded(
              child: _buildVitalItem(
                'O₂',
                vitals['oxygen_saturation'] ?? 'N/A',
                '%',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildVitalItem(
                'Temp',
                vitals['temperature'] ?? 'N/A',
                '°C',
              ),
            ),
            Expanded(
              child: _buildVitalItem(
                'RR',
                vitals['respiratory_rate'] ?? 'N/A',
                '/min',
              ),
            ),
            Expanded(
              child: Container(), // Empty space
            ),
          ],
        ),
        if (vitals['completed_at'] != null) ...[
          const SizedBox(height: 8),
          Text(
            'Last Updated: ${DateFormat('MMM dd, yyyy HH:mm').format((vitals['completed_at'] as Timestamp).toDate())}',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ],
    );
  }

  Widget _buildVitalItem(String label, String value, String unit) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        Text(unit, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }
}
