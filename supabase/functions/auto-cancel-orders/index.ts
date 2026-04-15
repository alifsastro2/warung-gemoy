import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

Deno.serve(async (_req) => {
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  )

  const now = new Date().toISOString()
  const today = now.split('T')[0]

  // Cari semua payment yang sudah expired dan masih pending
  const { data: expiredPayments } = await supabase
    .from('payments')
    .select('id, order_id')
    .eq('status', 'pending')
    .lt('expired_at', now)

  if (!expiredPayments || expiredPayments.length === 0) {
    return new Response(JSON.stringify({ cancelled: 0 }), {
      headers: { 'Content-Type': 'application/json' },
    })
  }

  const orderIds = expiredPayments.map((p: any) => p.order_id)

  // Ambil order items untuk kembalikan stok
  const { data: orderItems } = await supabase
    .from('order_items')
    .select('menu_id, qty')
    .in('order_id', orderIds)

  // Kembalikan stok
  if (orderItems && orderItems.length > 0) {
    for (const item of orderItems) {
      await supabase.rpc('decrement_used_qty', {
        p_menu_id: item.menu_id,
        p_date: today,
        p_qty: item.qty,
      })
    }
  }

  // Cancel semua payment yang expired
  await supabase
    .from('payments')
    .update({ status: 'cancelled' })
    .in('order_id', orderIds)
    .eq('status', 'pending')

  // Cancel semua order yang expired
  await supabase
    .from('orders')
    .update({ status: 'cancelled' })
    .in('id', orderIds)
    .eq('status', 'pending')

  console.log(`Auto-cancelled ${orderIds.length} orders`)

  return new Response(
    JSON.stringify({ cancelled: orderIds.length, order_ids: orderIds }),
    { headers: { 'Content-Type': 'application/json' } },
  )
})