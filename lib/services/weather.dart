import 'dart:convert';

import 'package:http/http.dart' as http;

/// Free weather from Open-Meteo (no key needed).
class WeatherReport {
  const WeatherReport({
    required this.place,
    required this.temperature,
    required this.condition,
    required this.max,
    required this.min,
    required this.rainChance,
  });

  final String place;
  final double temperature;
  final String condition;
  final double max;
  final double min;
  final int rainChance;

  /// Plain facts, used for the AI to phrase or for the offline reply.
  String facts() => 'Weather in $place now: ${temperature.round()}°C, $condition. '
      'Today: high ${max.round()}°C, low ${min.round()}°C, chance of rain $rainChance%.';
}

class WeatherService {
  static String _condition(int code) {
    if (code == 0) return 'clear sky';
    if (code <= 2) return 'partly cloudy';
    if (code == 3) return 'cloudy';
    if (code == 45 || code == 48) return 'foggy';
    if (code >= 51 && code <= 57) return 'drizzle';
    if (code >= 61 && code <= 67) return 'rain';
    if (code >= 71 && code <= 77) return 'snow';
    if (code >= 80 && code <= 82) return 'rain showers';
    if (code >= 95) return 'thunderstorm';
    return 'mixed weather';
  }

  Future<WeatherReport> fetch(String city) async {
    final geoRes = await http
        .get(Uri.https('geocoding-api.open-meteo.com', '/v1/search', {'name': city, 'count': '1', 'language': 'en'}))
        .timeout(const Duration(seconds: 15));
    final geo = jsonDecode(geoRes.body) as Map<String, dynamic>;
    final results = geo['results'];
    if (results is! List || results.isEmpty) {
      throw Exception('Could not find "$city"');
    }
    final place = results.first as Map<String, dynamic>;
    final res = await http
        .get(Uri.https('api.open-meteo.com', '/v1/forecast', {
          'latitude': '${place['latitude']}',
          'longitude': '${place['longitude']}',
          'current': 'temperature_2m,weather_code',
          'daily': 'temperature_2m_max,temperature_2m_min,precipitation_probability_max',
          'timezone': 'auto',
          'forecast_days': '1',
        }))
        .timeout(const Duration(seconds: 15));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final current = data['current'] as Map<String, dynamic>;
    final daily = data['daily'] as Map<String, dynamic>;
    num first(String key) {
      final list = daily[key];
      return list is List && list.isNotEmpty && list.first is num ? list.first as num : 0;
    }

    return WeatherReport(
      place: '${place['name']}',
      temperature: (current['temperature_2m'] as num).toDouble(),
      condition: _condition((current['weather_code'] as num).toInt()),
      max: first('temperature_2m_max').toDouble(),
      min: first('temperature_2m_min').toDouble(),
      rainChance: first('precipitation_probability_max').toInt(),
    );
  }
}
