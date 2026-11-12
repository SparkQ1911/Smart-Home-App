class AppConfig {
  const AppConfig._();

  static const apiBaseUrl = String.fromEnvironment(
    'SMART_HOME_SERVER_URL',
    defaultValue: 'https://smart-home-demo-api.onrender.com',
  );
}
