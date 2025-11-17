package cc.shinichi.library.tool.file

import android.content.Context
import androidx.media3.database.StandaloneDatabaseProvider
import androidx.media3.datasource.cache.LeastRecentlyUsedCacheEvictor
import androidx.media3.datasource.cache.SimpleCache
import java.io.File

/**
 * 仓库: <a href="http://git.xiaozhouintel.com/root/C-UI-App-Android">...</a>
 * 文件名: ExoCacheManager.java
 * 作者: kirito
 * 描述: 缓存管理器
 * 创建时间: 2025/11/13
 */
object ExoCacheManager {

    @Volatile
    private var simpleCache: SimpleCache? = null

    fun getSimpleCache(context: Context): SimpleCache {
        return simpleCache ?: synchronized(this) {
            simpleCache ?: run {
                val cacheDir = File(context.cacheDir, "exo_cache")
                val cacheEvictor = LeastRecentlyUsedCacheEvictor(2L * 1024 * 1024 * 1024) // 2GB
                val databaseProvider = StandaloneDatabaseProvider(context)
                SimpleCache(cacheDir, cacheEvictor, databaseProvider).also {
                    simpleCache = it
                }
            }
        }
    }

    fun release() {
        try {
            simpleCache?.release()
        } catch (e: Exception) {
            e.printStackTrace()
        } finally {
            simpleCache = null
        }
    }
}