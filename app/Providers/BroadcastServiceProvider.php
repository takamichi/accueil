<?php

namespace App\Providers;

use Illuminate\Broadcasting\BroadcastManager;
use Illuminate\Support\ServiceProvider;

class BroadcastServiceProvider extends ServiceProvider
{
    /**
     * Bootstrap any application services.
     *
     * @return void
     */
    public function boot()
    {
        $this->getManager()->routes();
    }

    private function getManager(): BroadcastManager
    {
        return $this->app->get(BroadcastManager::class);
    }
}
