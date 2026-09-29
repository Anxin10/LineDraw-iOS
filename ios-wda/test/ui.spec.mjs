import {test,expect} from '@playwright/test';
test('glass dashboard loads five coupons, no console errors, cannot start disconnected',async({page})=>{
  const errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.goto('/');await expect(page.locator('.item')).toHaveCount(5);
  await expect(page.getByRole('button',{name:'開始依序抽選'})).toBeDisabled();
  await page.locator('#accepted').check();
  await expect(page.getByRole('button',{name:'開始依序抽選'})).toBeDisabled();
  await expect(page.getByRole('button',{name:'儲存畫面診斷'})).toBeDisabled();
  await expect(page.locator('#mobile-pair')).toBeDisabled();
  await page.screenshot({path:'.runtime/ui-results/desktop.png',fullPage:true});
  expect(errors).toEqual([]);
});
test('compact layout stays within viewport and keeps stop control visible',async({page})=>{
  await page.setViewportSize({width:390,height:844});await page.goto('/');
  await expect(page.locator('.item')).toHaveCount(5);
  const overflow=await page.evaluate(()=>document.documentElement.scrollWidth>window.innerWidth);
  expect(overflow).toBe(false);
  await page.screenshot({path:'.runtime/ui-results/compact.png',fullPage:true});
  await page.locator('#stop').scrollIntoViewIfNeeded();await expect(page.locator('#stop')).toBeVisible();
});
