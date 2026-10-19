/* Genera la tabla carácter -> tecla evdev + modificadores para WaylandActivity
   a partir de un keymap real de xkbcommon (el mismo que usa sway).
   Uso: wayland/generar-teclado.sh [distribución]  (por defecto latam)

   Por cada tecla y nivel toma el primer juego de modificadores que da ese
   nivel; solo sirven Shift y AltGr (Mod5).  Las teclas muertas se anotan con
   su carácter combinante (U+0301 para dead_acute, etc.): WaylandActivity
   descompone "á" en tecla muerta + "a".  */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <xkbcommon/xkbcommon.h>

#define SHIFT 0x10000
#define ALTGR 0x20000

static struct { xkb_keysym_t sym; unsigned combinante; } muertas[] = {
  { XKB_KEY_dead_grave, 0x300 }, { XKB_KEY_dead_acute, 0x301 },
  { XKB_KEY_dead_circumflex, 0x302 }, { XKB_KEY_dead_tilde, 0x303 },
  { XKB_KEY_dead_diaeresis, 0x308 }, { XKB_KEY_dead_abovering, 0x30a },
  { XKB_KEY_dead_cedilla, 0x327 },
};

static unsigned codigos[0x110000];	/* 0 = sin asignar; si no, valor+1 */

int
main (int argc, char **argv)
{
  const char *layout = argc > 1 ? argv[1] : "latam";
  struct xkb_context *ctx = xkb_context_new (XKB_CONTEXT_NO_FLAGS);
  struct xkb_rule_names nombres = { .layout = layout };
  struct xkb_keymap *km = xkb_keymap_new_from_names (ctx, &nombres, 0);
  if (km == NULL)
    {
      fprintf (stderr, "no se pudo compilar el keymap %s\n", layout);
      return 1;
    }
  xkb_mod_index_t m_shift = xkb_keymap_mod_get_index (km, XKB_MOD_NAME_SHIFT);
  xkb_mod_index_t m_altgr = xkb_keymap_mod_get_index (km, "Mod5");

  for (xkb_level_index_t nivel = 0; nivel < 4; nivel++)
    for (xkb_keycode_t k = xkb_keymap_min_keycode (km); k <= xkb_keymap_max_keycode (km); k++)
      {
	/* Solo el teclado principal: nada del numérico ni teclas multimedia.  */
	if (k < 8 || k - 8 > 127 || nivel >= xkb_keymap_num_levels_for_key (km, k, 0))
	  continue;
	const xkb_keysym_t *syms;
	if (xkb_keymap_key_get_syms_by_level (km, k, 0, nivel, &syms) != 1)
	  continue;
	xkb_mod_mask_t mascaras[8];
	size_t n = xkb_keymap_key_get_mods_for_level (km, k, 0, nivel, mascaras, 8);
	int mods = -1;
	for (size_t i = 0; i < n && mods < 0; i++)
	  {
	    xkb_mod_mask_t m = mascaras[i];
	    xkb_mod_mask_t resto = m & ~((1u << m_shift) | (1u << m_altgr));
	    if (resto != 0)
	      continue;
	    mods = ((m >> m_shift) & 1 ? SHIFT : 0) | ((m >> m_altgr) & 1 ? ALTGR : 0);
	  }
	if (mods < 0)
	  continue;
	unsigned e = k - 8;	/* teclado numérico (evdev) */
	if (e == 55 || (e >= 71 && e <= 83) || e == 96 || e == 98 || e == 117
	    || e == 118 || e == 121)
	  continue;
	if (syms[0] >= XKB_KEY_KP_Space && syms[0] <= XKB_KEY_KP_9)
	  continue;
	unsigned cp = xkb_keysym_to_utf32 (syms[0]);
	for (size_t i = 0; i < sizeof muertas / sizeof muertas[0]; i++)
	  if (syms[0] == muertas[i].sym)
	    cp = muertas[i].combinante;
	if (cp < 0x20 || cp == 0x7f || cp >= 0x110000 || codigos[cp] != 0)
	  continue;
	codigos[cp] = ((k - 8) | mods) + 1;
      }

  printf ("package dev.ben4shot.glibcprueba;\n\n"
	  "// Generado por wayland/generar-teclado.sh con xkbcommon (distribución %s). No editar a mano.\n"
	  "final class Distribucion {\n"
	  "    static final String NOMBRE = \"%s\";\n\n"
	  "    // {carácter, evdev | 0x10000 Shift | 0x20000 AltGr}; U+03xx = tecla muerta\n"
	  "    static final int[] TABLA = {\n", layout, layout);
  int col = 0;
  for (unsigned cp = 0; cp < 0x110000; cp++)
    if (codigos[cp] != 0)
      {
	printf ("%s0x%x, 0x%x,", col == 0 ? "            " : " ", cp, codigos[cp] - 1);
	if (++col == 6)
	  {
	    printf ("\n");
	    col = 0;
	  }
      }
  printf ("%s    };\n}\n", col ? "\n" : "");
  xkb_keymap_unref (km);
  xkb_context_unref (ctx);
  return 0;
}
