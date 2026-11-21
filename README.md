# Bilheteira União Académica de Avintes

Gestão de reservas, lugares, bilhetes e entradas do auditório.

**Aplicação:** https://pviana3d.github.io/bilheteira-plebeus/

- `index.html` — a aplicação (página única), instalável em Android e iPhone (PWA: `manifest.webmanifest`, `sw.js`, `icons/`).
- `vendor/` — bibliotecas incluídas (leitor de códigos de barras e gerador de PDF); licenças em `vendor/LICENSES.md`. Os dados ficam no Supabase, protegidos por login e por perfis (Admin / User).
- `Abrir Bilheteira.bat` — atalho para o PC da bilheteira: abre a aplicação no Chrome com impressão direta na impressora predefinida (impressora térmica), sem janela de impressão.
- `Configurar impressao Chrome (80 mm).reg` / `(58 mm).reg` — configuração única do Chrome no PC da bilheteira: desliga cabeçalhos/rodapés e define o papel com o tamanho do bilhete (80 × 150 mm ou 58 × 100 mm).
- `supabase-schema.sql` — estrutura inicial da base de dados (referência).

A chave do Supabase que está no código é a chave pública (anon). O acesso aos dados é controlado pelas regras de segurança da base de dados: só emails da lista da equipa entram.
