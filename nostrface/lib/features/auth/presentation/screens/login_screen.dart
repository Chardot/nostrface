import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nostrface/core/services/key_management_service.dart';

// Provider for the currently entered private key
final privateKeyInputProvider = StateProvider<String>((ref) => '');

// Provider for checking if the entered key is valid
final isValidKeyProvider = Provider<bool>((ref) {
  final key = ref.watch(privateKeyInputProvider);
  final keyService = ref.watch(keyManagementServiceProvider);
  return keyService.isValidPrivateKey(key);
});

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final TextEditingController _privateKeyController = TextEditingController();
  bool _isProcessing = false;

  @override
  void dispose() {
    _privateKeyController.dispose();
    super.dispose();
  }

  Future<void> _handlePrivateKeyInput() async {
    final String privateKey = _privateKeyController.text.trim();
    
    // Debug information
    if (privateKey.startsWith('nsec1')) {
      debugPrint('Processing nsec key: ${privateKey.substring(0, 8)}...');
    }
    
    setState(() {
      _isProcessing = true;
    });

    try {
      final keyService = ref.read(keyManagementServiceProvider);
      
      // Store the private key
      await keyService.storePrivateKey(privateKey);
      
      // Force refresh of authentication state
      ref.invalidate(isLoggedInProvider);
      ref.invalidate(currentPublicKeyProvider);
      
      // Verify the key was stored correctly
      final isLoggedIn = await keyService.hasPrivateKey();
      
      if (kDebugMode) {
        print('Login success check: $isLoggedIn');
      }
      
      // Wait a moment for the providers to update, then navigate
      if (mounted) {
        // We'll use a single navigation instead of showing a snackbar and then navigating
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            context.go('/discovery');
          }
        });
      }
    } catch (e) {
      debugPrint('Error storing private key: $e');
      // Show error locally in the login screen without a snackbar
      setState(() {
        _isProcessing = false;
      });
      
      // Display error in a more stable way if context is still valid
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Login Error'),
            content: Text('Error saving private key: ${e.toString()}'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _handleGenerateKeys() async {
    setState(() {
      _isProcessing = true;
    });

    try {
      final keyService = ref.read(keyManagementServiceProvider);
      await keyService.generateKeyPair();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('New keys generated successfully!')),
        );
        context.go('/discovery');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating keys: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _handleConnectExtension() async {
    // This is a placeholder for NIP-07 extension integration
    // In a real app, you would use a platform channel or web-specific code
    // to interact with browser extensions
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('NIP-07 extension support coming soon!')),
    );
    
    // For now, just navigate to the discovery screen
    context.go('/discovery');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect to Nostr'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.person_outline,
              size: 120,
              color: Colors.black54,
            ),
            const SizedBox(height: 40),
            const Text(
              'Welcome to NostrFace',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              'Discover interesting profiles from the Nostr network',
              style: TextStyle(
                fontSize: 16,
                color: Colors.black54,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: _isProcessing ? null : _handleConnectExtension,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('Connect with Extension'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _privateKeyController,
              decoration: InputDecoration(
                labelText: 'Private Key (nsec or hex)',
                hintText: 'Enter your private key',
                border: const OutlineInputBorder(),
                helperText: 'Paste your nsec key or private key hex',
                suffixIcon: _privateKeyController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _privateKeyController.clear();
                        ref.read(privateKeyInputProvider.notifier).state = '';
                      },
                    )
                  : null,
              ),
              obscureText: true,
              onChanged: (value) {
                ref.read(privateKeyInputProvider.notifier).state = value;
              },
            ),
            const SizedBox(height: 16),
            Consumer(
              builder: (context, ref, child) {
                final isValid = ref.watch(isValidKeyProvider);
                final privateKey = ref.watch(privateKeyInputProvider);
                
                return ElevatedButton(
                  onPressed: _isProcessing || !isValid
                    ? null 
                    : _handlePrivateKeyInput,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isProcessing
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(privateKey.startsWith('nsec1') 
                        ? 'Login with nsec' 
                        : 'Login with Private Key'),
                );
              },
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _isProcessing ? null : _handleGenerateKeys,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('Generate New Keys'),
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: _isProcessing 
                ? null 
                : () => context.go('/discovery'),
              child: const Text('Skip for now (Read-only)'),
            ),
          ],
        ),
      ),
    );
  }
}