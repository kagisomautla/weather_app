import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dvt/apis/get_weather.dart';
import 'package:dvt/controls/drawer.dart';
import 'package:dvt/controls/text.dart';
import 'package:dvt/helpers/local_storage/delete.dart';
import 'package:dvt/helpers/local_storage/fetch.dart';
import 'package:dvt/helpers/local_storage/send.dart';
import 'package:dvt/models/connection.dart';
import 'package:dvt/models/locations.dart';
import 'package:dvt/providers/locations.dart';
import 'package:dvt/providers/system.dart';
import 'package:dvt/screens/home/components/weather.dart';
import 'package:dvt/screens/home/components/forecast.dart';
import 'package:dvt/utils/constants.dart';
import 'package:dvt/utils/functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_google_places_hoc081098/flutter_google_places_hoc081098.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_api_headers/google_api_headers.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_webservice/places.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:developer' as developer;

class HomeScreen extends StatefulWidget {
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? address;
  bool loadingHomePage = true;
  dynamic currentWeather;
  List<dynamic> forecast = [];
  Image? currentWeatherImage;
  Color? backgroundColor;
  bool isSearching = false;
  bool showMap = false;
  GoogleMapController? mapController;
  CameraPosition? cameraPosition;
  LatLng startLocation = LatLng(-26.195246, 28.034088);
  String location = "Search Location";
  bool showWeatherBySearch = false;
  LatLng? searchLatLng;
  LatLng? position;
  bool loadingData = true;
  SharedPreferences? sharedPreferences;
  List<dynamic> listOfFavoriteLocations = [];
  Icon? weatherIcon;
  LocationsModel? selectedLocationData;

  Map source = {ConnectivityResult.none: false};
  final NetworkConnectivity networkConnectivity = NetworkConnectivity.instance;
  String string = '';

  @override
  void initState() {
    initScreen();
    super.initState();
  }

  initScreen() async {
    initConnectivity(); //check connection first before execution.
    LocationsProvider locationsProvider = Provider.of<LocationsProvider>(context, listen: false);
    SystemProvider systemProvider = Provider.of<SystemProvider>(context, listen: false);

    DateTime now = DateTime.now();
    final String lastWeatherUpdate = DateFormat('MMM d, H:mm a').format(now);

    // Do this if user is not connected to internet
    if (systemProvider.isOnline == false) {
      dynamic offlineWeatherFromStorage = await fetchOfflineWeather();
      if (offlineWeatherFromStorage != null) {
        dynamic decodedData = json.decode(offlineWeatherFromStorage);
        setState(() {
          selectedLocationData = LocationsModel(
            location: LatLng(decodedData['location'][0], decodedData['location'][1]),
            address: decodedData['address'],
            weather: decodedData['weather'],
            timeOfLastUpdate: decodedData['time_of_last_update'],
          );
        });
      }
      setState(() {
        loadingHomePage = false;
        loadingData = false;
      });
      return;
    }

    // Do this if user is connected to the internet
    if (showWeatherBySearch) {
      //show weather by search location
      setState(() {
        position = searchLatLng;
      });
    } else {
      //show weather by current location
      position = await getCurrentPosition(context);
    }

    // Fetch data favorite locations from storage and set to provider
    dynamic favoriteLocationsFromStorage = await fetchFavoriteLocations();
    if (favoriteLocationsFromStorage != null) {
      setState(() {
        List<dynamic> decodedLocations = json.decode(favoriteLocationsFromStorage);
        locationsProvider.favoriteLocations = decodedLocations
            .map((e) => LocationsModel(
                  location: LatLng(e['location'][0], e['location'][1]),
                  address: e['address'],
                ))
            .toList();
      });
    }

    if (position != null) {
      address = await getAddressFromLatLng(position!.latitude, position!.longitude);
      await getWeather(
        context: context,
        type: 'weather',
        lat: position!.latitude.toString(),
        lon: position!.longitude.toString(),
      ).then((response) async {
        if (response.statusCode == 200) {
          currentWeather = json.decode(response.body) as Map<String, dynamic>;
          setState(() {
            selectedLocationData = LocationsModel(location: position, address: address, timeOfLastUpdate: lastWeatherUpdate, weather: currentWeather);
          });
          storeOfflineWeather(value: selectedLocationData!);
        } else {
          showSnackBar(context: context, message: 'Failed to load weather... ${response.statusCode}.');
        }
      });

      await getWeather(
        context: context,
        type: 'forecast',
        lat: position!.latitude.toString(),
        lon: position!.longitude.toString(),
      ).then((response) async {
        if (response.statusCode == 200) {
          dynamic body = json.decode(response.body) as Map<String, dynamic>;
          List<dynamic> listOfForecast = body['list'];
          forecast = extractDaysOfTheWeekData(listOfForecast);
        } else {
          showSnackBar(context: context, message: 'Failed to load forecast... ${response.statusCode}.');
        }
      });

      setState(() {
        locationsProvider.selectedLocation = selectedLocationData;
      });

      //check if the current/search location is part of the favorites
      checkIfLocationIsFavorite();
    }

    setState(() {
      loadingHomePage = false;
      loadingData = false;
    });
  }

  checkIfLocationIsFavorite() {
    LocationsProvider locationsProvider = Provider.of<LocationsProvider>(context, listen: false);
    locationsProvider.isFavorite = false;

    int index = locationsProvider.favoriteLocations.indexWhere((e) => e.address == selectedLocationData!.address);

    if (index > -1) {
      setState(() {
        locationsProvider.isFavorite = true;
      });
    }
  }

  initConnectivity() {
    SystemProvider systemProvider = Provider.of<SystemProvider>(context, listen: false);
    networkConnectivity.initialise();
    networkConnectivity.myStream.listen((src) {
      setState(() {
        source = src;
      });
      switch (source.keys.toList()[0]) {
        case ConnectivityResult.mobile:
        case ConnectivityResult.wifi:
          setState(() {
            systemProvider.isOnline = true;
          });

          break;
        case ConnectivityResult.none:
          setState(() {
            systemProvider.isOnline = false;
          });
          break;
        default:
          string = 'Offline';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    LocationsProvider locationsProvider = Provider.of<LocationsProvider>(context);
    SystemProvider systemProvider = Provider.of<SystemProvider>(context);
    print('reload');
    if (selectedLocationData != null) {
      switch (selectedLocationData!.weather!['weather'][0]['main'].toString().toLowerCase()) {
        case 'clear':
          setState(() {
            currentWeatherImage = Image.asset('assets/images/forest_sunny.png', fit: BoxFit.fill);
            backgroundColor = kSunny;
            weatherIcon = Icon(
              FontAwesomeIcons.cloudSun,
              color: kSunny,
              size: 50,
            );
          });
          break;
        case 'clouds':
          setState(() {
            currentWeatherImage = Image.asset('assets/images/forest_cloudy.png', fit: BoxFit.fill);
            backgroundColor = kCloudy;
            weatherIcon = Icon(
              FontAwesomeIcons.cloud,
              color: kCloudy,
              size: 50,
            );
          });
          break;
        case 'rain':
        case 'thuderstorm':
        case 'drizzle':
        case 'snow':
          setState(() {
            currentWeatherImage = Image.asset(
              'assets/images/forest_rainy.png',
              fit: BoxFit.fill,
            );
            backgroundColor = kRainy;
            weatherIcon = Icon(
              FontAwesomeIcons.cloudRain,
              color: kRainy,
              size: 50,
            );
          });
          break;
        default:
          setState(() {
            currentWeatherImage = Image.asset('assets/images/forest_sunny.png', fit: BoxFit.fill);
            backgroundColor = kSunny;
            weatherIcon = Icon(
              FontAwesomeIcons.cloudSun,
              color: kRainy,
              size: 50,
            );
          });
      }
    }
    return loadingHomePage == true
        ? Scaffold(
            backgroundColor: Colors.white,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/images/loader.gif',
                    height: MediaQuery.of(context).size.height / 6,
                  ),
                ],
              ),
            ),
          )
        : Scaffold(
            backgroundColor: Colors.white,
            drawer: systemProvider.isOnline == true
                ? DrawerControl(
                    backgroundColor: backgroundColor,
                    weatherIcon: weatherIcon,
                    address: address,
                    weatherDescription: selectedLocationData!.weather?['weather'][0]['main'].toString(),
                  )
                : null,
            appBar: AppBar(
              backgroundColor: backgroundColor,
              iconTheme: IconThemeData(color: Colors.white),
              actions: [
                showWeatherBySearch
                    ? GestureDetector(
                        onTap: () {
                          setState(() {
                            showWeatherBySearch = false;
                            loadingData = true;
                            location = "Search Location";
                          });
                          initScreen();
                        },
                        child: Row(
                          children: [
                            Icon(
                              Icons.refresh,
                              color: Colors.white,
                            ),
                            SizedBox(
                              width: 5,
                            ),
                            TextControl(
                              text: 'Use my location',
                              color: Colors.white,
                            ),
                            SizedBox(
                              width: 10,
                            ),
                          ],
                        ),
                      )
                    : Container(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10.0),
                  child: systemProvider.isOnline == false
                      ? Center(
                          child: TextControl(
                            text: 'Last updated at: ${selectedLocationData!.timeOfLastUpdate}',
                            color: Colors.white,
                          ),
                        )
                      : GestureDetector(
                          onTap: () async {
                            setState(() {
                              locationsProvider.isFavorite = true;
                            });

                            int index = locationsProvider.favoriteLocations.indexWhere((e) => e.address == selectedLocationData!.address);

                            if (index == -1) {
                              locationsProvider.favoriteLocations = [...locationsProvider.favoriteLocations, selectedLocationData!];
                              storeFavoriteLocations(value: [...locationsProvider.favoriteLocations]);
                              showSnackBar(context: context, message: 'Location added to favorites.', textColor: backgroundColor);
                            } else {
                              showSnackBar(context: context, message: 'Location is already favorited.', textColor: backgroundColor);
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.only(right: 20),
                            child: Center(
                              child: FaIcon(
                                FontAwesomeIcons.solidHeart,
                                color: locationsProvider.isFavorite ? Colors.red : Colors.white,
                              ),
                            ),
                          ),
                        ),
                ),
                systemProvider.isOnline == false
                    ? Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              loadingData = true;
                              showWeatherBySearch = true;
                              searchLatLng = LatLng(selectedLocationData!.location!.latitude, selectedLocationData!.location!.longitude);
                            });
                            initScreen();
                          },
                          child: Center(
                            child: FaIcon(
                              FontAwesomeIcons.arrowsRotate,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      )
                    : Container(),
              ],
            ),
            body: Stack(
              children: [
                loadingData
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SpinKitCircle(
                              color: backgroundColor,
                            ),
                            SizedBox(
                              height: 20,
                            ),
                            TextControl(
                              text: 'Loading weather based on your ${showWeatherBySearch ? 'search' : 'current'} location...',
                              size: TextProps.normal,
                            ),
                          ],
                        ),
                      )
                    : SingleChildScrollView(
                        physics: BouncingScrollPhysics(
                          decelerationRate: ScrollDecelerationRate.fast,
                        ),
                        child: Column(
                          children: [
                            WeatherComponent(
                              address: selectedLocationData!.address,
                              currentWeather: selectedLocationData!.weather,
                              currentWeatherImage: currentWeatherImage,
                            ),
                            ForecastComponent(
                              backgroundColor: backgroundColor,
                              currentWeather: selectedLocationData!.weather,
                              forecast: forecast,
                            )
                          ],
                        ),
                      ),
                systemProvider.isOnline == true
                    ? Positioned(
                        child: InkWell(
                          onTap: () async {
                            var place = await PlacesAutocomplete.show(
                              context: context,
                              apiKey: dotenv.env['API_KEY'],
                              mode: Mode.overlay,
                              strictbounds: false,
                            );

                            if (place != null) {
                              setState(() {
                                location = place.description.toString();
                              });

                              final plist = GoogleMapsPlaces(
                                apiKey: dotenv.env['API_KEY'],
                                apiHeaders: await GoogleApiHeaders().getHeaders(),
                              );
                              String placeid = place.placeId ?? "0";
                              final detail = await plist.getDetailsByPlaceId(placeid);
                              final geometry = detail.result.geometry!;
                              final lat = geometry.location.lat;
                              final lang = geometry.location.lng;
                              var newlatlang = LatLng(lat, lang);
                              mapController?.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(target: newlatlang, zoom: 17)));
                              setState(() {
                                loadingData = true;
                                showWeatherBySearch = true;
                                searchLatLng = LatLng(geometry.location.lat, geometry.location.lng);
                              });
                              initScreen();
                            }
                          },
                          child: Padding(
                            padding: EdgeInsets.all(15),
                            child: Card(
                              child: Container(
                                padding: EdgeInsets.all(0),
                                width: MediaQuery.of(context).size.width - 40,
                                child: ListTile(
                                  leading: Icon(Icons.search),
                                  title: TextControl(
                                    text: location,
                                    size: TextProps.normal,
                                    isBold: true,
                                  ),
                                  dense: true,
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                    : Container()
              ],
            ),
          );
  }
}
