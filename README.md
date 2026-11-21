# Bilheteira Plebeus

Gestão de reservas, lugares, bilhetes e entradas do auditório.

**Aplicação:** https://pviana3d.github.io/bilheteira-plebeus/

- `index.html` — a aplicação (página única). Os dados ficam no Supabase, protegidos por login e por perfis (Admin / User).
- `Abrir Bilheteira.bat` — atalho para o PC da bilheteira: abre a aplicação no Chrome com impressão direta na impressora predefinida (impressora térmica), sem janela de impressão.
- `supabase-schema.sql` — estrutura inicial da base de dados (referência).

A chave do Supabase que está no código é a chave pública (anon). O acesso aos dados é controlado pelas regras de segurança da base de dados: só emails da lista da equipa entram.
