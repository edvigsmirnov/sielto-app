package dev.edvig.sielto

import androidx.core.content.FileProvider

// Its own class, so it never merges with a plugin's FileProvider.
class UpdateFileProvider : FileProvider()
