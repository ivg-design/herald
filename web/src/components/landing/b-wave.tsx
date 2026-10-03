/** Static waveform bars (decorative). Heights are fractions of the container height. */
export const WAVE = [0.3, 0.55, 0.4, 0.8, 1, 0.6, 0.35, 0.7, 0.9, 0.5, 0.65, 0.95, 0.45, 0.3, 0.75, 0.55, 0.85, 0.4, 0.6, 0.3, 0.5];

export default function MiniWave({ className = "", bars = 12 }: { className?: string; bars?: number }) {
  return (
    <span aria-hidden className={`inline-flex items-end gap-[3px] ${className}`}>
      {WAVE.slice(0, bars).map((h, i) => (
        <span key={i} className="w-[3px] rounded-full bg-accent" style={{ height: `${Math.round(h * 100)}%` }} />
      ))}
    </span>
  );
}
