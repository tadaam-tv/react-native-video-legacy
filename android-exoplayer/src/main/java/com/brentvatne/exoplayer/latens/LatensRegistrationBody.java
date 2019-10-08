package com.brentvatne.exoplayer.latens;

import com.google.gson.annotations.SerializedName;

class LatensRegistrationBody {
    @SerializedName("LatensRegistration")
    LatensRegistration latensRegistration;

    @SerializedName("Payload")
    String payload;

    @SerializedName("AuthToken")
    String authToken;
}
