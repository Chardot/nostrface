# Direct Message Button in Discovery View

## Overview

The Direct Message (DM) button replaces the star/superlike button in the discovery view, allowing users to quickly initiate conversations with discovered profiles. This feature enhances user engagement by providing immediate communication options directly from the discovery interface.

## Problem Statement

The original design included a star button (similar to Tinder's superlike) in the middle of the three action buttons. However, since our app doesn't implement a superlike feature, this button served no purpose and wasted valuable UI real estate. Users needed a quick way to message interesting profiles without having to navigate to the full profile view first.

## Solution Design

### 1. Button Replacement

The star button was replaced with a message icon button:

```dart
return _buildActionButton(
  icon: Icons.message,  // Changed from Icons.star
  color: Colors.blue,   // Kept blue for visual consistency
  onPressed: hasProfiles ? () async {
    // DM functionality
  } : null,
);
```

### 2. Authentication Check

Direct messaging requires authentication to ensure message delivery and maintain user privacy:

```dart
// Check if user is logged in
final isLoggedIn = await ref.read(isLoggedInProvider.future);

if (!isLoggedIn && context.mounted) {
  // Show login prompt dialog
  showDialog(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: const Text('Login Required'),
      content: const Text(
        'You need to be logged in to send direct messages. Would you like to log in now?'
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            context.push('/login');
          },
          child: const Text('Log In'),
        ),
      ],
    ),
  );
  return;
}
```

### 3. Navigation Flow

Currently, the button navigates to the profile screen with a comment for future enhancement:

```dart
// Navigate to profile screen with DM intent
final profile = profiles[currentIndex];
if (context.mounted) {
  // For now, navigate to profile screen
  // TODO: When DM screen is implemented, navigate directly to DM
  context.go('/discovery/profile/${profile.pubkey}');
}
```

## User Experience Flow

1. **Unauthenticated User**:
   - Taps DM button → Login dialog appears
   - Can choose to login or cancel
   - If login chosen → Redirected to login screen

2. **Authenticated User**:
   - Taps DM button → Navigates to profile screen
   - Future: Will navigate directly to DM conversation

## Implementation Details

### Button Layout

The three-button layout remains unchanged:
- **Left (Red)**: Discard/Skip profile
- **Middle (Blue)**: Send Direct Message (previously Star)
- **Right (Green/Red)**: Follow/Unfollow profile

### Visual Consistency

- Icon size and button styling remain consistent with other action buttons
- Blue color maintained for the middle button position
- Disabled state handling when no profiles are available

## Future Enhancements

### 1. Direct DM Navigation

When the DM screen is implemented, update the navigation:

```dart
// Future implementation
context.push('/direct-messages/${profile.pubkey}');
```

### 2. Quick Message Templates

Consider adding quick message options:
- "Hi, I found your profile interesting!"
- "Love your posts about [topic]"
- Custom opener based on profile content

### 3. Message Preview

Show recent conversation preview if users have chatted before:
- Last message snippet
- Unread message count
- Time of last interaction

## Technical Considerations

### Route Configuration

The DM route needs to be added to the app router:

```dart
GoRoute(
  path: '/direct-messages/:recipientId',
  name: 'direct-messages',
  builder: (context, state) {
    final recipientId = state.pathParameters['recipientId'] ?? '';
    return DirectMessagesScreen(recipientId: recipientId);
  },
),
```

### State Management

Consider implementing:
- Message draft persistence
- Typing indicators
- Read receipts
- Online status

## Testing Checklist

1. **Button Functionality**:
   - [ ] DM button appears with message icon
   - [ ] Button is blue colored
   - [ ] Button is disabled when no profiles available

2. **Authentication Flow**:
   - [ ] Login dialog appears for unauthenticated users
   - [ ] Dialog has clear messaging about DM requirements
   - [ ] Login navigation works correctly
   - [ ] Cancel button closes dialog properly

3. **Navigation**:
   - [ ] Authenticated users navigate to profile screen
   - [ ] Profile ID is passed correctly
   - [ ] Back navigation returns to discovery

## Conclusion

The DM button replacement transforms an unused feature into a valuable communication tool. By providing quick access to messaging from the discovery view, users can immediately connect with interesting profiles, increasing engagement and facilitating meaningful connections on the platform. The implementation maintains visual consistency while adding practical functionality that aligns with user expectations from modern social applications.