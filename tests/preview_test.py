"""Browser tests for the standalone preview; no FiveM or NUI endpoint required."""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import os
from pathlib import Path
import threading
import unittest

from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]


class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, *_):
        pass


class PreviewTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(('127.0.0.1', 0), partial(QuietHandler, directory=str(ROOT / 'web')))
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()
        cls.origin = f'http://127.0.0.1:{cls.server.server_port}'
        cls.playwright = sync_playwright().start()
        cls.browser = cls.playwright.chromium.launch(executable_path=os.getenv('CHROMIUM_PATH', '/usr/lib/chromium/chromium'), headless=True, args=['--no-sandbox'])

    @classmethod
    def tearDownClass(cls):
        cls.browser.close()
        cls.playwright.stop()
        cls.server.shutdown()
        cls.server.server_close()

    def setUp(self):
        self.context = self.browser.new_context(viewport={'width':1440,'height':1000})
        self.page = self.context.new_page()
        self.errors = []
        self.external = []
        self.page.on('pageerror', lambda error: self.errors.append(str(error)))
        self.page.on('request', lambda request: self.external.append(request.url) if not request.url.startswith(self.origin) else None)
        self.page.goto(self.origin, wait_until='networkidle')

    def tearDown(self):
        self.assertEqual(self.errors, [])
        self.assertEqual(self.external, [])
        self.context.close()

    def garage(self):
        self.page.locator('[data-action="garage"][data-id="1"]').first.click()

    def action(self, name):
        self.page.locator(f'[data-action="{name}"]').click()

    def row(self, plate):
        return self.page.locator('tbody tr').filter(has_text=plate)

    def test_navigation_filters_and_roles(self):
        self.assertEqual(self.page.locator('.garage-card').count(), 2)
        self.garage()
        self.assertEqual(self.page.locator('tbody tr').count(), 3)
        self.page.locator('#fleet-search').fill('depanneuse')
        self.assertEqual(self.page.locator('tbody tr').count(), 1)
        self.action('clear-filters')
        self.page.locator('#fleet-filter').select_option('out')
        self.assertEqual(self.page.locator('tbody tr').count(), 1)
        self.page.locator('#preview-role').select_option('employee')
        self.assertEqual(self.page.locator('tbody tr').count(), 2)
        self.assertEqual(self.page.locator('[data-action="register"]').count(), 0)
        self.assertEqual(self.page.locator('#nav-garages .nav-item').count(), 1)

    def test_bridge_import_persistence_and_return(self):
        self.garage()
        self.page.locator('button.button[data-action="store"]').click()
        self.assertEqual(self.row('OKOK001').count(), 1)
        self.assertIn('Au garage', self.row('OKOK001').inner_text())
        self.assertFalse(self.page.evaluate("EnterpriseGaragePreview.bootstrap().garages[0].vehicles.find(v=>v.plate==='OKOK001').bridge == null"))
        self.page.reload(wait_until='networkidle')
        self.garage()
        self.assertEqual(self.row('OKOK001').count(), 1)
        self.row('OKOK001').locator('[data-action="remove-vehicle"]').click()
        self.action('confirm-sensitive')
        self.assertEqual(self.row('OKOK001').count(), 0)
        self.assertEqual(self.page.locator('#preview-vehicle option[value="OKOK001"]').count(), 1)

    def test_manual_import_withdraw_and_store(self):
        self.garage()
        self.page.locator('#preview-vehicle').select_option('OKOK002')
        self.action('register')
        self.action('scan-vehicle')
        self.page.locator('#register-form [name="label"]').fill('Véhicule transféré')
        self.action('confirm-register')
        self.assertIn('Véhicule transféré', self.row('OKOK002').inner_text())
        self.row('OKOK002').locator('[data-action="withdraw"]').click()
        self.action('confirm-withdraw')
        self.assertIn('En circulation', self.row('OKOK002').inner_text())
        self.row('OKOK002').locator('[data-action="store"]').click()
        self.assertIn('Au garage', self.row('OKOK002').inner_text())

    def test_categories_rename_and_assignment(self):
        self.garage()
        self.row('AEGIS01').locator('[data-action="rename-vehicle"]').click()
        self.page.locator('#rename-form [name="label"]').fill('Dépannage express')
        self.action('confirm-rename')
        self.assertIn('Dépannage express', self.row('AEGIS01').inner_text())
        self.action('tab-categories')
        self.action('new-category')
        self.page.locator('#category-form [name="name"]').fill('Interventions urgentes')
        self.action('save-category')
        self.assertEqual(self.page.locator('.category-card').count(), 3)
        self.action('tab-fleet')
        self.row('AEGIS01').locator('[data-action="classify-vehicle"]').click()
        self.page.locator('#assign-form [name="categoryId"]').select_option(label='Interventions urgentes')
        self.action('confirm-assign')
        self.assertIn('Interventions urgentes', self.row('AEGIS01').inner_text())

    def test_settings_acl_and_points(self):
        self.garage()
        self.action('tab-settings')
        self.action('edit-permissions')
        self.page.locator('[data-acl="garage"] .acl-mode').select_option('list')
        self.page.locator('[data-acl="garage"] [data-role="grade"][value="4"]').check()
        self.page.locator('[data-acl="garage"] [data-role="employee"][value="demo:lea"]').check()
        self.action('save-permissions')
        rule = self.page.evaluate('EnterpriseGaragePreview.bootstrap().garages[0].permissions.access_rules')
        self.assertEqual(rule['grades'], [4])
        self.assertEqual(rule['identifiers'], ['demo:lea'])
        self.page.locator('[data-action="add-point"][data-kind="spawn"]').click()
        self.page.locator('#point-form [name="label"]').fill('Sortie atelier')
        self.action('capture')
        self.action('save-point')
        self.assertIn('Sortie atelier', self.page.locator('#content').inner_text())

    def test_create_close_reopen_and_reset(self):
        self.action('new-garage')
        self.page.locator('#garage-form [name="name"]').fill('Annexe de test')
        self.page.locator('#garage-form [name="job"]').fill('mechanic')
        self.action('save-garage')
        self.assertEqual(self.page.locator('#nav-garages .nav-item').count(), 3)
        self.page.locator('#close-button').click()
        self.assertFalse(self.page.locator('#app').is_visible())
        self.page.locator('#preview-open').click()
        self.assertTrue(self.page.locator('#app').is_visible())
        self.page.locator('#preview-reset').click()
        self.assertEqual(self.page.locator('.garage-card').count(), 2)

    def test_mobile_layout(self):
        self.page.set_viewport_size({'width':390,'height':844})
        self.garage()
        self.assertLessEqual(self.page.evaluate('document.documentElement.scrollWidth'), 390)
        self.assertTrue(self.page.locator('#preview-role').is_visible())
        self.assertTrue(self.page.locator('#app').is_visible())

    def test_fivem_never_loads_demo(self):
        self.page.add_init_script("window.GetParentResourceName = () => 'aegis_enterprise_garages'")
        self.page.reload(wait_until='networkidle')
        self.assertEqual(self.page.locator('.preview-bar').count(), 0)
        self.assertFalse(self.page.locator('#app').is_visible())
        self.assertTrue(self.page.evaluate('window.EnterpriseGaragePreview === undefined'))


if __name__ == '__main__':
    unittest.main(verbosity=2)
