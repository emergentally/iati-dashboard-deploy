module.exports = {
  apps: [
    {
      name: '{{ name }}',
      exec_mode: 'cluster',
      instances: 'max',
      port: '{{ pm2_port }}',
      // Served from the swapped-in copy, not .output, so a failed build
      // leaves the previous release running.
      script: '.output-latest/server/index.mjs',
      // A crash writes a core file into the app directory; watch mode treats
      // that as a change and restarts, turning a crash into a loop. Nothing
      // in a built bundle needs watching - deploys restart pm2 explicitly.
      watch: false,
      // Without a cap a leaking or looping worker grows until V8 aborts at
      // its ~4GB heap limit. Recycle well before that.
      max_memory_restart: '700M',
      env: {
        NITRO_PORT: '{{ pm2_port }}',
        PORT: '{{ pm2_port }}'
      }
    }
  ]
}
