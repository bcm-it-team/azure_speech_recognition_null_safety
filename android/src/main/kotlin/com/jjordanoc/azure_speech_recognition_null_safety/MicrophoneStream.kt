package com.jjordanoc.azure_speech_recognition_null_safety

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder

import com.microsoft.cognitiveservices.speech.audio.AudioStreamFormat
import com.microsoft.cognitiveservices.speech.audio.PullAudioInputStreamCallback
import kotlin.math.log10
import kotlin.math.sqrt

class MicrophoneStream(
    private val sampleRate: Int = 16000,
    private val onSoundLevel: (Double) -> Unit,
) : PullAudioInputStreamCallback() {
    private val audioFormat = AudioStreamFormat.getWaveFormatPCM(sampleRate.toLong(), 16.toShort(), 1.toShort())
    private val recorder: AudioRecord
    private var lastLevelUpdateAt = 0L
    @Volatile
    private var isClosed = false

    init {
        val format = AudioFormat.Builder()
            .setSampleRate(sampleRate)
            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
            .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
            .build()
        val bufferSize = AudioRecord.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        ).coerceAtLeast(sampleRate / 10)

        recorder = AudioRecord.Builder()
            .setAudioSource(MediaRecorder.AudioSource.VOICE_RECOGNITION)
            .setAudioFormat(format)
            .setBufferSizeInBytes(bufferSize)
            .build()
        recorder.startRecording()
    }

    fun getFormat(): AudioStreamFormat = audioFormat

    override fun read(bytes: ByteArray): Int {
        if (isClosed) return 0
        val bytesRead = try {
            recorder.read(bytes, 0, bytes.size)
        } catch (_: IllegalStateException) {
            return 0
        }
        if (bytesRead > 1) {
            reportSoundLevel(bytes, bytesRead)
        }
        return bytesRead
    }

    private fun reportSoundLevel(bytes: ByteArray, bytesRead: Int) {
        val now = System.currentTimeMillis()
        if (now - lastLevelUpdateAt < 100) return
        lastLevelUpdateAt = now

        var sumOfSquares = 0.0
        var sampleCount = 0
        var index = 0
        while (index + 1 < bytesRead) {
            val sample = ((bytes[index + 1].toInt() shl 8) or (bytes[index].toInt() and 0xff)).toShort().toInt()
            sumOfSquares += sample.toDouble() * sample
            sampleCount++
            index += 2
        }
        if (sampleCount == 0) return

        val rms = sqrt(sumOfSquares / sampleCount)
        val decibels = 20 * log10((rms / Short.MAX_VALUE).coerceAtLeast(0.000001))
        val normalizedLevel = ((decibels + 60) * (100.0 / 60)).coerceIn(0.0, 100.0)
        onSoundLevel(normalizedLevel)
    }

    override fun close() {
        if (isClosed) return
        isClosed = true
        if (recorder.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
            recorder.stop()
        }
        recorder.release()
    }
}