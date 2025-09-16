import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geocoding/geocoding.dart';
import 'package:odp/pages/movie_details.dart';
import 'package:odp/pages/profile.dart';
import 'package:odp/pages/bookings_history_page.dart';
import 'package:odp/widgets/moviecard.dart';

class HomePage1 extends StatefulWidget {
  final User? user;

  const HomePage1({super.key, this.user});

  @override
  _HomePage1State createState() => _HomePage1State();
}

class _HomePage1State extends State<HomePage1> {
  int _selectedIndex = 0;
  String _searchText = '';
  final Set<String> _selectedGenreFilters = {};
  final Set<String> _selectedLanguageFilters = {};
  String _selectedLocation = 'All Areas';
  List<String> _availableLocations = ['All Areas'];

  @override
  void initState() {
    super.initState();
    _loadAvailableLocations();
  }

  Future<void> _loadAvailableLocations() async {
    try {
      final theatres = await FirebaseFirestore.instance
          .collection('movie_theatres')
          .where('theatre_status', isEqualTo: 'Verified')
          .get();
      final Set<String> localities = {};

      for (var doc in theatres.docs) {
        final theatreData = doc.data();
        final location = theatreData['location']?.toString() ?? '';
        if (location.isNotEmpty) {
          localities.add(location);
        }
      }

      setState(() {
        _availableLocations = ['All Areas', ...localities];
        if (!_availableLocations.contains(_selectedLocation)) {
          _selectedLocation = 'All Areas';
        }
      });
    } catch (e) {
      // Handle error if needed
    }
  }

  void _onItemTapped(int index) {
    if (index == 1) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => BookingsPage()),
      );
    } else if (index == 2) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => ProfilePage()),
      );
    } else {
      setState(() {
        _selectedIndex = index;
      });
    }
  }

  Widget _buildMoviesList() {
    return Column(
      children: [
        // Search Bar
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Material(
            elevation: 2,
            borderRadius: BorderRadius.circular(30),
            child: TextFormField(
              onChanged: (value) {
                setState(() {
                  _searchText = value;
                });
              },
              style: TextStyle(color: Colors.black),
              decoration: InputDecoration(
                hintText: 'Search movies...',
                hintStyle: TextStyle(color: Colors.black54),
                filled: true,
                fillColor: Colors.white,
                contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: Icon(Icons.search, color: Colors.red),
              ),
            ),
          ),
        ),

        // Location Filter
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: DropdownButtonFormField<String>(
            value: _selectedLocation,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Location',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
              filled: true,
              fillColor: Colors.white,
            ),
            items: _availableLocations.map((location) {
              return DropdownMenuItem<String>(
                value: location,
                child: Text(location),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _selectedLocation = value;
                });
              }
            },
          ),
        ),
        SizedBox(height: 10),

        // Genre Filter
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('movies').snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return SizedBox.shrink();
            final movies = snapshot.data!.docs;
            final Set<String> allGenres = {};
            for (var doc in movies) {
              final movieData = doc.data() as Map<String, dynamic>;
              final genres = List<String>.from(movieData['genre'] ?? []);
              allGenres.addAll(genres);
            }
            final genresList = allGenres.toList();
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ChoiceChip(
                      label: Text('All Genres'),
                      selected: _selectedGenreFilters.isEmpty,
                      selectedColor: Colors.red.shade100,
                      onSelected: (selected) {
                        setState(() {
                          _selectedGenreFilters.clear();
                        });
                      },
                    ),
                    ...genresList.map((genre) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: ChoiceChip(
                        label: Text(genre),
                        selected: _selectedGenreFilters.contains(genre),
                        selectedColor: Colors.red.shade100,
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              _selectedGenreFilters.add(genre);
                            } else {
                              _selectedGenreFilters.remove(genre);
                            }
                          });
                        },
                      ),
                    )),
                  ],
                ),
              ),
            );
          },
        ),
        SizedBox(height: 10),

        // Movies Grid
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('movies')
                .where('status', isEqualTo: 'Now Showing')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(child: CircularProgressIndicator());
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return _buildEmptyMoviesState();
              }

              final movies = snapshot.data!.docs;

              // Filter movies based on search and filters
              final filteredMovies = movies.where((doc) {
                final movieData = doc.data() as Map<String, dynamic>;
                final movieTitle = movieData['title']?.toString().toLowerCase() ?? '';
                final genres = List<String>.from(movieData['genre'] ?? []);
                final languages = List<String>.from(movieData['language'] ?? []);

                final matchesSearch = movieTitle.contains(_searchText.toLowerCase());
                final matchesGenre = _selectedGenreFilters.isEmpty ||
                    _selectedGenreFilters.any((g) => genres.contains(g));
                final matchesLanguage = _selectedLanguageFilters.isEmpty ||
                    _selectedLanguageFilters.any((l) => languages.contains(l));

                return matchesSearch && matchesGenre && matchesLanguage;
              }).toList();

              if (filteredMovies.isEmpty) {
                return Center(
                  child: Text(
                    'No movies found for your filters.',
                    style: TextStyle(color: Colors.grey[600], fontSize: 16),
                  ),
                );
              }

              return GridView.builder(
                padding: EdgeInsets.all(16),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.7,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: filteredMovies.length,
                itemBuilder: (context, index) {
                  final doc = filteredMovies[index];
                  final movieData = doc.data() as Map<String, dynamic>;

                  return MovieCard(
                    imageUrl: movieData['posterUrl'] ?? '',
                    title: movieData['title'] ?? 'Unknown Movie',
                    description: movieData['description'] ?? '',
                    documentId: doc.id,
                    docname: movieData['title'] ?? 'Unknown Movie',
                    chips: List<String>.from(movieData['genre'] ?? []),
                    duration: movieData['duration'] ?? 0,
                    rating: movieData['rating'] ?? '',
                    language: List<String>.from(movieData['language'] ?? []),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyMoviesState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.movie_creation_outlined,
            size: 100,
            color: Colors.red.shade200,
          ),
          SizedBox(height: 20),
          Text(
            'No Movies Available',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.red.shade700,
            ),
          ),
          SizedBox(height: 10),
          Text(
            'Check back later for new movie releases and showtimes',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'BookMyBiz',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        backgroundColor: Colors.red.shade800,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.red.shade50, Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: _buildMoviesList(),
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.movie),
            label: 'Movies',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.confirmation_number),
            label: 'Bookings',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.red.shade800,
        onTap: _onItemTapped,
      ),
    );
  }
}